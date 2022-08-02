module AMMPractice::CoinSwap {
    use std::string;
    use std::option::{Self};
    use std::signer;
    use aptos_std::event::{Self, EventHandle};
    use aptos_framework::coin::{Self, Coin, BurnCapability, MintCapability};
    use aptos_framework::coins::{Self};

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
        amount_a: u64,
        amount_b: u64,
    }

    struct CoinStore<phantom CoinA, phantom CoinB> has key {
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
    ) acquires CoinStore, Capabilities {
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

        let creator = signer::address_of(account);
        deposit<CoinA, CoinB, CoinLP>(account, creator, amount_a, amount_b);
    }

    public entry fun deposit<CoinA, CoinB, CoinLP>(
        account: &signer,
        creator: address,
        amount_a: u64,
        amount_b: u64,
    ) acquires CoinStore, Capabilities {
        let coin_a = coin::withdraw<CoinA>(account, amount_a);
        let coin_b = coin::withdraw<CoinB>(account, amount_b);
        
        deposit_internal<CoinA, CoinB, CoinLP>(account, creator, coin_a, coin_b);
    }

    fun deposit_internal<CoinA, CoinB, CoinLP>(
        account: &signer,
        creator: address,
        coin_a: Coin<CoinA>,
        coin_b: Coin<CoinB>,
    ) acquires CoinStore, Capabilities {
        let depositor = signer::address_of(account);
        let amount_a = coin::value<CoinA>(&coin_a);
        let amount_b = coin::value<CoinB>(&coin_b);

        if (!exists<CoinStore<CoinA, CoinB>>(creator)) {
            move_to(account, CoinStore<CoinA, CoinB>{
                coin_a,
                coin_b,
                deposit_events: event::new_event_handle<DepositEvent>(account),
                withdraw_events: event::new_event_handle<WithdrawEvent>(account),
                swap_events: event::new_event_handle<SwapEvent>(account),
            });
        } else {
            let coin_store = borrow_global_mut<CoinStore<CoinA, CoinB>>(creator);
            coin::merge(&mut coin_store.coin_a, coin_a);
            coin::merge(&mut coin_store.coin_b, coin_b);
        };
        
        let coin_store = borrow_global_mut<CoinStore<CoinA, CoinB>>(creator);
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
        let lp_supply = option::borrow(&coin::supply<CoinLP>());
        if (*lp_supply == 0) {
            let coins_minted = coin::mint(100 * 1000000u64, &capabilities.mint_cap);
            coin::deposit(depositor, coins_minted);
        } else {
            let pool_amount_a = coin::value<CoinA>(&coin_store.coin_a);
            let pool_amount_b = coin::value<CoinB>(&coin_store.coin_b);

            let a_ratio = (*lp_supply) * (amount_a as u128) / ((pool_amount_a - amount_a) as u128);
            let b_ratio = (*lp_supply) * (amount_b as u128) / ((pool_amount_b - amount_b) as u128);
            let minimum: u128 = if (a_ratio > b_ratio) b_ratio else a_ratio;

            // mint minimum amount of LP coin
            let coins_minted = coin::mint((minimum as u64), &capabilities.mint_cap);
            coin::deposit(depositor, coins_minted);
        }
    }

    fun pool_info<CoinA, CoinB, CoinLP>(creator: address): (u64, u64, u128) acquires CoinStore {
        let coin_store = borrow_global<CoinStore<CoinA, CoinB>>(creator);
        let lp_supply = option::borrow(&coin::supply<CoinLP>());
        
        (coin::value<CoinA>(&coin_store.coin_a), coin::value<CoinB>(&coin_store.coin_b), *lp_supply)
    }

    //
    // Tests
    //

    #[test_only]
    use aptos_framework::account::{Self};
    
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
    ) acquires CoinStore, Capabilities {
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
    public entry fun test_deposit(
        account: signer,
    ) acquires CoinStore, Capabilities {
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
        );

        assert!(coin::balance<FakeCoinA>(account_address) == 9890000000, 1);
        assert!(coin::balance<FakeCoinB>(account_address) == 9880000000, 2);
        assert!(coin::balance<FakeCoinLP>(account_address) == 110000000, 3);

        let (amount_a, amount_b, amount_lp) = pool_info<FakeCoinA, FakeCoinB, FakeCoinLP>(account_address);
        assert!(amount_a == 110 * 1000000u64, 4);
        assert!(amount_b == 120 * 1000000u64, 5);
        assert!(amount_lp == 110 * 1000000u128, 6);
    }
}