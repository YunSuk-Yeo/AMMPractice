module AMMPractice::CoinSwap {
    use std::string;
    use std::option::{Self, Option};
    use std::signer;
    use aptos_std::event::{Self, EventHandle};
    use aptos_framework::coin::{Self, Coin, BurnCapability, MintCapability};
    use aptos_framework::coins::{Self};

    const ENO_MINIMUM_RECEIVE: u64 = 0;
    const ENO_ALREADY_INITIALIZED: u64 = 1;
    const ENO_POOL_NOT_INITIALIZED: u64 = 2;

    struct Capabilities<phantom CoinLP> has key {
        mint_cap: MintCapability<CoinLP>,
        burn_cap: BurnCapability<CoinLP>,
    }

    /// Event emitted when some amount of coins are deposited into an account.
    struct DepositEvent has drop, store {
        depositor: address,
        amount_a: u64,
        amount_b: u64,
    }

    /// Event emitted when some amount of coins are withdrawn from an account.
    struct WithdrawEvent has drop, store {
        withdrawer: address,
        amount_a: u64,
        amount_b: u64,
    }

    /// Event emitted when some amount of coins are swapped into an account.
    struct SwapEvent has drop, store {
        swapper: address,
        amount_offer: u64,
        amount_ask: u64,
        is_reverse: bool,
    }

    struct PoolStore<phantom CoinA, phantom CoinB> has key {
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
        deposit_events: EventHandle<DepositEvent>,
        withdraw_events: EventHandle<WithdrawEvent>,
        swap_events: EventHandle<SwapEvent>
    }

    public entry fun initialize<CoinA, CoinB, CoinLP>(
        account: &signer,
        amount_a: u64,
        amount_b: u64,
    ) acquires PoolStore, Capabilities {
        let creator = signer::address_of(account);
        assert!(
            !exists<PoolStore<CoinA, CoinB>>(creator) && 
            !exists<PoolStore<CoinB, CoinA>>(creator), 
            ENO_ALREADY_INITIALIZED,
        );

        let (mint_cap, burn_cap) = coin::initialize<CoinLP>(
            account,
            string::utf8(b"LP coin"),
            string::utf8(b"LP"),
            6u64,
            true,
        );

        // register creator account to CoinLP
        coins::register<CoinLP>(account);

        move_to(account, Capabilities<CoinLP>{
            mint_cap,
            burn_cap,
        });

        deposit_internal<CoinA, CoinB, CoinLP>(
            account, 
            creator, 
            amount_a, 
            amount_b, 
            option::none(),
        );
    }
  
    public entry fun deposit<CoinA, CoinB, CoinLP>(
        account: &signer,
        creator: address,
        amount_a: u64,
        amount_b: u64,
        minimum_receive_lp: u64,
    ) acquires PoolStore, Capabilities {
        if (exists<PoolStore<CoinA, CoinB>>(creator)) {
            deposit_internal<CoinA, CoinB, CoinLP>(
                account, 
                creator, 
                amount_a, 
                amount_b, 
                option::some(minimum_receive_lp),
            );
        } else if (exists<PoolStore<CoinB, CoinA>>(creator)) {
            deposit_internal<CoinB, CoinA, CoinLP>(
                account,
                creator,
                amount_b,
                amount_a,
                option::some(minimum_receive_lp),
            );
        } else {
            abort ENO_POOL_NOT_INITIALIZED
        };
    }

    fun deposit_internal<CoinA, CoinB, CoinLP>(
        account: &signer,
        creator: address,
        amount_a: u64,
        amount_b: u64,
        minimum_receive_lp: Option<u64>,
    ) acquires PoolStore, Capabilities {
        let depositor = signer::address_of(account);
        let coin_a = coin::withdraw<CoinA>(account, amount_a);
        let coin_b = coin::withdraw<CoinB>(account, amount_b);

        if (!exists<PoolStore<CoinA, CoinB>>(creator)) {
            move_to(account, PoolStore<CoinA, CoinB>{
                coin_a,
                coin_b,
                deposit_events: event::new_event_handle<DepositEvent>(account),
                withdraw_events: event::new_event_handle<WithdrawEvent>(account),
                swap_events: event::new_event_handle<SwapEvent>(account),
            });
        } else {
            let coin_store = borrow_global_mut<PoolStore<CoinA, CoinB>>(creator);
            coin::merge(&mut coin_store.coin_a, coin_a);
            coin::merge(&mut coin_store.coin_b, coin_b);
        };
        
        let coin_store = borrow_global_mut<PoolStore<CoinA, CoinB>>(creator);
        event::emit_event<DepositEvent>(
            &mut coin_store.deposit_events,
            DepositEvent {
                depositor,
                amount_a,
                amount_b,
            }
        );
        
        // mint LP token
        let capabilities = borrow_global<Capabilities<CoinLP>>(creator);
        let supply_lp = *option::borrow(&coin::supply<CoinLP>());
        if (supply_lp == 0) {
            let coins_minted = coin::mint(100 * 1000000u64, &capabilities.mint_cap);
            coin::deposit(depositor, coins_minted);
        } else {
            let pool_amount_a = coin::value<CoinA>(&coin_store.coin_a);
            let pool_amount_b = coin::value<CoinB>(&coin_store.coin_b);

            let a_ratio = (supply_lp) * (amount_a as u128) / ((pool_amount_a - amount_a) as u128);
            let b_ratio = (supply_lp) * (amount_b as u128) / ((pool_amount_b - amount_b) as u128);

            let minimum: u128 = if (a_ratio > b_ratio) b_ratio else a_ratio;
            if (option::is_some(&minimum_receive_lp)) {
                let minimum_receive_lp: u128 = (*option::borrow(&minimum_receive_lp) as u128);
                assert!(minimum >= minimum_receive_lp, ENO_MINIMUM_RECEIVE);
            };

            // mint minimum amount of LP coin
            let coins_minted = coin::mint((minimum as u64), &capabilities.mint_cap);
            coin::deposit(depositor, coins_minted);
        }
    }

    public entry fun withdraw<CoinA, CoinB, CoinLP>(
        account: &signer,
        creator: address,
        amount_lp: u64,
        minimum_receive_a: u64,
        minimum_receive_b: u64,
    ) acquires PoolStore, Capabilities {
        if (exists<PoolStore<CoinA, CoinB>>(creator)) {
            withdraw_internal<CoinA, CoinB, CoinLP>(
                account, 
                creator, 
                amount_lp,
                minimum_receive_a,
                minimum_receive_b,
            );
        } else if (exists<PoolStore<CoinB, CoinA>>(creator)) {
            withdraw_internal<CoinB, CoinA, CoinLP>(
                account, 
                creator, 
                amount_lp,
                minimum_receive_b,
                minimum_receive_a,
            );
        } else {
            abort ENO_POOL_NOT_INITIALIZED
        };
    }

    fun withdraw_internal<CoinA, CoinB, CoinLP>(
        account: &signer,
        creator: address,
        amount_lp: u64,
        minimum_receive_a: u64,
        minimum_receive_b: u64,
    ) acquires PoolStore, Capabilities {
        let withdrawer = signer::address_of(account);

        let coin_store = borrow_global_mut<PoolStore<CoinA, CoinB>>(creator);
        let supply_lp = *option::borrow(&coin::supply<CoinLP>());
        let pool_amount_a = coin::value<CoinA>(&coin_store.coin_a);
        let pool_amount_b = coin::value<CoinB>(&coin_store.coin_b);

        // return LP portion of coins
        let amount_a = ((pool_amount_a as u128) * (amount_lp as u128) / supply_lp as u64);
        let amount_b = ((pool_amount_b as u128) * (amount_lp as u128) / supply_lp as u64);

        assert!(amount_a >= minimum_receive_a, ENO_MINIMUM_RECEIVE);
        assert!(amount_b >= minimum_receive_b, ENO_MINIMUM_RECEIVE);

        // withdraw coins from PoolStore
        let coin_a = coin::extract<CoinA>(&mut coin_store.coin_a, amount_a);
        let coin_b = coin::extract<CoinB>(&mut coin_store.coin_b, amount_b);

        // deposit withdrawn coins
        coin::deposit<CoinA>(withdrawer, coin_a);
        coin::deposit<CoinB>(withdrawer, coin_b);

        // burn LP coin
        let capabilities = borrow_global<Capabilities<CoinLP>>(creator);
        coin::burn_from(signer::address_of(account), amount_lp, &capabilities.burn_cap);

        event::emit_event<WithdrawEvent>(
            &mut coin_store.withdraw_events,
            WithdrawEvent {
                withdrawer,
                amount_a,
                amount_b,
            }
        );
    }

    public entry fun swap<CoinA, CoinB>(
        account: &signer,
        creator: address,
        amount_offer: u64,
        minimum_receive: u64,
    ) acquires PoolStore {
        if (exists<PoolStore<CoinA, CoinB>>(creator)) {
            swap_internal<CoinA, CoinB>(
                account, 
                creator, 
                amount_offer, 
                minimum_receive, 
                false,
            );
        } else if (exists<PoolStore<CoinB, CoinA>>(creator)) {
            swap_internal<CoinB, CoinA>(
                account, 
                creator, 
                amount_offer, 
                minimum_receive, 
                true,
            );
        } else {
            abort ENO_POOL_NOT_INITIALIZED
        };
    }

    fun swap_internal<CoinA, CoinB>(
        account: &signer,
        creator: address,
        amount_offer: u64,
        minimum_receive: u64,
        is_reverse: bool,
    ) acquires PoolStore {
        let swapper = signer::address_of(account);

        // Load Pool Info
        let coin_store = borrow_global_mut<PoolStore<CoinA, CoinB>>(creator);
        let (offer_pool, ask_pool) = if (!is_reverse) {
            (coin::value<CoinA>(&coin_store.coin_a), coin::value<CoinB>(&coin_store.coin_b))
        } else {
            (coin::value<CoinB>(&coin_store.coin_b), coin::value<CoinA>(&coin_store.coin_a))
        };

        // k = x * y
        // k = (x + x') * (y - y')
        // y' = y - k / (x + x')
        let amount_ask = ask_pool - offer_pool * ask_pool / (offer_pool + amount_offer);
        assert!(amount_ask >= minimum_receive, ENO_MINIMUM_RECEIVE);

        if (!is_reverse) {
            let coin_withdrawn = coin::withdraw<CoinA>(account, amount_offer);
            coin::merge<CoinA>(&mut coin_store.coin_a, coin_withdrawn);

            let coin_extracted = coin::extract<CoinB>(&mut coin_store.coin_b, amount_ask);
            coin::deposit(swapper, coin_extracted);
        } else {
            let coin_withdrawn = coin::withdraw<CoinB>(account, amount_offer);
            coin::merge<CoinB>(&mut coin_store.coin_b, coin_withdrawn);

            let coin_extracted = coin::extract<CoinA>(&mut coin_store.coin_a, amount_ask);
            coin::deposit(swapper, coin_extracted);
        };

        event::emit_event<SwapEvent>(
            &mut coin_store.swap_events,
            SwapEvent {
                swapper,
                amount_offer,
                amount_ask,
                is_reverse,
            }
        );
    }

    public fun pool_info<CoinA, CoinB, CoinLP>(creator: address): (u64, u64, u128) acquires PoolStore {
        if (exists<PoolStore<CoinA, CoinB>>(creator)) {
            let coin_store = borrow_global<PoolStore<CoinA, CoinB>>(creator);
            let supply_lp = *option::borrow(&coin::supply<CoinLP>());
            
            (coin::value<CoinA>(&coin_store.coin_a), coin::value<CoinB>(&coin_store.coin_b), supply_lp)
        } else if (exists<PoolStore<CoinB, CoinA>>(creator)) {
            let coin_store = borrow_global<PoolStore<CoinB, CoinA>>(creator);
            let supply_lp = *option::borrow(&coin::supply<CoinLP>());
        
            (coin::value<CoinA>(&coin_store.coin_b), coin::value<CoinB>(&coin_store.coin_a), supply_lp)   
        } else {
            abort ENO_POOL_NOT_INITIALIZED
        }
    }

    //
    // Tests
    //

    #[test_only]
    use aptos_framework::account::{Self};

    // #[test_only]
    // use std::debug::{Self};
    
    #[test_only]
    struct FakeCoinACapabilities has key {
        mint_cap: MintCapability<FakeCoinA>,
        burn_cap: BurnCapability<FakeCoinA>,
    }

    #[test_only]
    struct FakeCoinBCapabilities has key {
        mint_cap: MintCapability<FakeCoinB>,
        burn_cap: BurnCapability<FakeCoinB>,
    }

    #[test_only]
    struct FakeCoinA { }

    #[test_only]
    struct FakeCoinB { }

    #[test_only]
    struct FakeCoinLP { }

    #[test_only]
    public fun create_fake_coins(
        source: &signer,
    ) {
        let name = string::utf8(b"Fake Coin A");
        let symbol = string::utf8(b"FCA");
        let (mint_cap, burn_cap) = coin::initialize<FakeCoinA>(
            source,
            name,
            symbol,
            6,
            false,
        );

        coins::register<FakeCoinA>(source);

        let coins_minted = coin::mint<FakeCoinA>(10000000000u64, &mint_cap);
        coin::deposit(signer::address_of(source), coins_minted);
        move_to(source, FakeCoinACapabilities {
            mint_cap,
            burn_cap,
        });


        let name = string::utf8(b"Fake Coin B");
        let symbol = string::utf8(b"FCB");
        let (mint_cap, burn_cap) = coin::initialize<FakeCoinB>(
            source,
            name,
            symbol,
            6,
            false,
        );

        coins::register<FakeCoinB>(source);

        let coins_minted = coin::mint<FakeCoinB>(10000000000u64, &mint_cap);
        coin::deposit(signer::address_of(source), coins_minted);
        move_to(source, FakeCoinBCapabilities {
            mint_cap,
            burn_cap,
        });
    }

    #[test(account = @0x2)]
    public entry fun test_initialize(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100 * 1000000u64,
            100 * 1000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9900000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9900000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 100000000, 3);

        let (amount_a, amount_b, amount_lp) = pool_info<FakeCoinA, FakeCoinB, FakeCoinLP>(account_address);
        assert!(amount_a == 100 * 1000000u64, 4);
        assert!(amount_b == 100 * 1000000u64, 5);
        assert!(amount_lp == 100 * 1000000u128, 6);
    }

    #[test(account = @0x2)]
    #[expected_failure(abort_code = 0x1)]
    public entry fun fail_initialize_duplicated(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100 * 1000000u64,
            100 * 1000000u64,
        );

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100 * 1000000u64,
            100 * 1000000u64,
        );
    }

    #[test(account = @0x2)]
    #[expected_failure(abort_code = 0x1)]
    public entry fun fail_initialize_reverse(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100 * 1000000u64,
            100 * 1000000u64,
        );

        initialize<FakeCoinB, FakeCoinA, FakeCoinLP>(
            &account,
            100 * 1000000u64,
            100 * 1000000u64,
        );
    }

    #[test(account = @0x2)]
    public entry fun test_deposit(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100000000u64,
            100000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9900000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9900000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 100000000, 3);

        // deposit in different ratio
        deposit<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            account_address,
            10 * 1000000u64,
            20 * 1000000u64,
            5 * 1000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9890000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9880000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 110000000, 3);

        let (amount_a, amount_b, amount_lp) = pool_info<FakeCoinA, FakeCoinB, FakeCoinLP>(account_address);
        assert!(amount_a == 110 * 1000000u64, 4);
        assert!(amount_b == 120 * 1000000u64, 5);
        assert!(amount_lp == 110 * 1000000u128, 6);

        // check reverse way is working
        let (amount_b, amount_a, amount_lp) = pool_info<FakeCoinB, FakeCoinA, FakeCoinLP>(account_address);
        assert!(amount_a == 110 * 1000000u64, 4);
        assert!(amount_b == 120 * 1000000u64, 5);
        assert!(amount_lp == 110 * 1000000u128, 6);
    }

    #[test(account = @0x2)]
    #[expected_failure(abort_code = 0x0)]
    public entry fun fail_deposit(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100000000u64,
            100000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9900000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9900000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 100000000, 3);

        // deposit in different ratio
        deposit<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            account_address,
            10 * 1000000u64,
            20 * 1000000u64,
            12 * 1000000u64,
        );
    }

    #[test(account = @0x2)]
    public entry fun test_withdraw(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100000000u64,
            100000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9900 * 1000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9900 * 1000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 100 * 1000000, 3);

        // withdraw half
        withdraw<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            account_address,
            50 * 1000000u64,
            50 * 1000000u64,
            50 * 1000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9950 * 1000000, 4);
        assert!(coin::balance<FakeCoinB>(account_address) == 9950 * 1000000, 5);
        assert!(coin::balance<FakeCoinLP>(account_address) == 50 * 1000000, 6);

        let (amount_a, amount_b, amount_lp) = pool_info<FakeCoinA, FakeCoinB, FakeCoinLP>(account_address);
        assert!(amount_a == 50 * 1000000u64, 4);
        assert!(amount_b == 50 * 1000000u64, 5);
        assert!(amount_lp == 50 * 1000000u128, 6);
    }

    #[test(account = @0x2)]
    #[expected_failure(abort_code = 0x0)]
    public entry fun fail_withdraw_due_to_a(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100000000u64,
            100000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9900 * 1000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9900 * 1000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 100 * 1000000, 3);

        // withdraw half
        withdraw<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            account_address,
            50 * 1000000u64,
            60 * 1000000u64,
            50 * 1000000u64,
        );
    }

    #[test(account = @0x2)]
    #[expected_failure(abort_code = 0x0)]
    public entry fun fail_withdraw_due_to_b(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100000000u64,
            100000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9900 * 1000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9900 * 1000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 100 * 1000000, 3);

        // withdraw half
        withdraw<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            account_address,
            50 * 1000000u64,
            50 * 1000000u64,
            60 * 1000000u64,
        );
    }

    #[test(account = @0x2)]
    public entry fun test_swap(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100000000u64,
            100000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9900000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9900000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 100000000, 3);

        swap<FakeCoinA, FakeCoinB>(
            &account,
            account_address,
            10 * 1000000u64,
            9090910u64,
        );

        let (amount_a, amount_b, amount_lp) = pool_info<FakeCoinA, FakeCoinB, FakeCoinLP>(account_address);
        assert!(amount_a == 110 * 1000000u64, 4);
        assert!(amount_b == 90909090u64, 5);
        assert!(amount_lp == 100 * 1000000u128, 6);
    }

    #[test(account = @0x2)]
    public entry fun test_swap_reverse(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100000000u64,
            100000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9900000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9900000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 100000000, 3);

        swap<FakeCoinB, FakeCoinA>(
            &account,
            account_address,
            10 * 1000000u64,
            9090910u64,
        );

        let (amount_a, amount_b, amount_lp) = pool_info<FakeCoinB, FakeCoinA, FakeCoinLP>(account_address);
        assert!(amount_a == 110 * 1000000u64, 4);
        assert!(amount_b == 90909090u64, 5);
        assert!(amount_lp == 100 * 1000000u128, 6);
    }

    #[test(account = @0x2)]
    #[expected_failure(abort_code = 0x0)]
    public entry fun fail_swap(
        account: signer,
    ) acquires PoolStore, Capabilities {
        let account_address = signer::address_of(&account);
        account::create_account(account_address);
        create_fake_coins(&account);

        initialize<FakeCoinA, FakeCoinB, FakeCoinLP>(
            &account,
            100000000u64,
            100000000u64,
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9900000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9900000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 100000000, 3);

        swap<FakeCoinA, FakeCoinB>(
            &account,
            account_address,
            10 * 1000000u64,
            9090911u64,
        );
    }
}