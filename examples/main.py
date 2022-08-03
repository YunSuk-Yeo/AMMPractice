#!/usr/bin/env python3

from dotenv import load_dotenv
from os import getenv

from transaction import Account, FaucetClient, RestClient
from coin import Coin
from coin_swap import CoinSwap

REST_URL = "http://0.0.0.0:8080"
FAUCET_URL = "http://0.0.0.0:8081"

# load .env
load_dotenv()

if __name__ == "__main__":
    private_key = getenv("SEED")
    account = Account(bytes.fromhex(private_key))
    print(f"Address: {account.address()}")

    rest_client = RestClient(REST_URL)
    # rest_account = rest_client.account(account.address())
    # print(rest_account)

    rest_balance = rest_client.account_balance(account.address())
    if not (rest_balance and
            "data" in rest_balance and
            "coin" in rest_balance["data"] and
            "value" in rest_balance["data"]["coin"] and
            int(rest_balance["data"]["coin"]["value"]) > 0):

        faucet_client = FaucetClient(FAUCET_URL, rest_client)
        faucet_client.fund_account(account.address(), 10_000_000)

    coin_client = Coin(REST_URL)

    # initialize two coins
    if not rest_client.account_resource(account.address(), f"0x1::coin::CoinInfo<0x{account.address()}::CoinA::CoinA>"):
        tx_hash = coin_client.initialize_coin(account, "A")

        print(f"Initializing CoinA: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    if not rest_client.account_resource(account.address(), f"0x1::coin::CoinInfo<0x{account.address()}::CoinB::CoinB>"):
        tx_hash = coin_client.initialize_coin(account, "B")

        print(f"Initializing CoinB: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    # register account for both coins
    if not rest_client.account_resource(account.address(), f"0x1::coin::CoinStore<0x{account.address()}::CoinA::CoinA>"):
        tx_hash = coin_client.register_coin(account, account.address(), "A")

        print(f"Register Account for CoinA: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    if not rest_client.account_resource(account.address(), f"0x1::coin::CoinStore<0x{account.address()}::CoinB::CoinB>"):
        tx_hash = coin_client.register_coin(account, account.address(), "B")

        print(f"Register Account for CoinB: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    if not(int(coin_client.get_balance(account.address(), account.address(), "A")) > 0):
        tx_hash = coin_client.mint_coin(
            account, "A", account.address(), 10000 * 1000000)

        print(f"Mint CoinA: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    if not(int(coin_client.get_balance(account.address(), account.address(), "B")) > 0):
        tx_hash = coin_client.mint_coin(
            account, "B", account.address(), 10000 * 1000000)

        print(f"Mint CoinB: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    balance_A = coin_client.get_balance(
        account.address(), account.address(), "A")
    balance_B = coin_client.get_balance(
        account.address(), account.address(), "B")

    print(f"Balance of CoinA: {balance_A}")
    print(f"Balance of CoinB: {balance_B}")

    coin_swap_client = CoinSwap(REST_URL)

    # initialize coin swap
    if not rest_client.account_resource(account.address(), f"0x{account.address()}::CoinSwap::PoolStore<0x{account.address()}::CoinA::CoinA, 0x{account.address()}::CoinB::CoinB>"):
        tx_hash = coin_swap_client.initialize_coin_swap(
            account, account.address(), str(100 * 1000000), str(100 * 1000000))

        print(f"Initializing CoinSwap: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

        # print balances
        balance_A = coin_client.get_balance(
            account.address(), account.address(), "A")
        balance_B = coin_client.get_balance(
            account.address(), account.address(), "B")
        
        print(f"Balance of CoinA: {balance_A}")
        print(f"Balance of CoinB: {balance_B}")

    # print pool info
    pool_info = coin_swap_client.get_pool_info(
        account.address(), account.address()
    )
    print(f"Pool A: {pool_info[0]}, Pool B: {pool_info[1]}")

    # execute swap
    tx_hash = coin_swap_client.swap(
            account, account.address(), str(10 * 1000000), str(1 * 1000000), False)

    print(f"Swapping {10} CoinA => CoinB: {tx_hash}")
    rest_client.wait_for_transaction(tx_hash)

    # print pool info
    pool_info = coin_swap_client.get_pool_info(
        account.address(), account.address()
    )
    print(f"Pool A: {pool_info[0]}, Pool B: {pool_info[1]}")