#!/usr/bin/env python3

from dotenv import load_dotenv
from os import getenv

from transaction import Account, FaucetClient, RestClient, TESTNET_URL, FAUCET_URL
from coin import Coin

# load .env
load_dotenv()

if __name__ == "__main__":
    private_key = getenv("SEED")
    account = Account(bytes.fromhex(private_key))
    print(f"Address: {account.address()}")

    rest_client = RestClient(TESTNET_URL)
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

    coin_client = Coin(TESTNET_URL)

    # initialize two coins
    if not rest_client.account_resource(account.address(), f"0x1::coin::CoinInfo<0x{account.address()}::ACoin::ACoin>"):
        tx_hash = coin_client.initialize_coin_A(account)

        print(f"Initializing ACoin: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    if not rest_client.account_resource(account.address(), f"0x1::coin::CoinInfo<0x{account.address()}::BCoin::BCoin>"):
        tx_hash = coin_client.initialize_coin_B(account)

        print(f"Initializing BCoin: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    # register account for both coins
    if not rest_client.account_resource(account.address(), f"0x1::coin::CoinStore<0x{account.address()}::ACoin::ACoin>"):
        tx_hash = coin_client.register_coin(account, account.address(), "A")

        print(f"Register Account for ACoin: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    if not rest_client.account_resource(account.address(), f"0x1::coin::CoinStore<0x{account.address()}::BCoin::BCoin>"):
        tx_hash = coin_client.register_coin(account, account.address(), "B")

        print(f"Register Account for BCoin: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    if not(int(coin_client.get_balance(account.address(), account.address(), "A")) > 0):
        tx_hash = coin_client.mint_coin(
            account, "A", account.address(), 100000000)

        print(f"Mint ACoin: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    if not(int(coin_client.get_balance(account.address(), account.address(), "B")) > 0):
        tx_hash = coin_client.mint_coin(
            account, "B", account.address(), 100000000)

        print(f"Mint BCoin: {tx_hash}")
        rest_client.wait_for_transaction(tx_hash)

    balance_A = coin_client.get_balance(
        account.address(), account.address(), "A")
    balance_B = coin_client.get_balance(
        account.address(), account.address(), "B")

    print(f"Balance of ACoin: {balance_A}")
    print(f"Balance of BCoin: {balance_B}")

    