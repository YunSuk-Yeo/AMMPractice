#!/usr/bin/env python3

from typing import Optional
from transaction import Account, RestClient, TESTNET_URL, FAUCET_URL


class Coin(RestClient):
    def initialize_coin(self, account_from: Account, coin_type: str) -> Optional[str]:
        """ Initialize a new coin B with the given coin type. """
        payload = {
            "type": "script_function_payload",
            "function": "0x1::managed_coin::initialize",
            "type_arguments": [f"0x{account_from.address()}::{coin_type}Coin::{coin_type}Coin"],
            "arguments": [
                "B Coin".encode("utf-8").hex(),
                "B".encode("utf-8").hex(),
                "6",
                False
            ]
        }

        res = self.execute_transaction_with_payload(account_from, payload)
        return str(res["hash"])

    def register_coin(self, account_receiver: Account, coin_type_address: str, coin_type: str) -> str:
        """ Register the receiver account to receive transfers for the new coin. """

        payload = {
            "type": "script_function_payload",
            "function": "0x1::coin::register",
            "type_arguments": [f"0x{coin_type_address}::{coin_type}Coin::{coin_type}Coin"],
            "arguments": []
        }
        res = self.execute_transaction_with_payload(account_receiver, payload)
        return str(res["hash"])

    def mint_coin(
        self,
        account_coin_owner: Account,
        coin_type: str,
        receiver_address: str,
        amount: int
    ) -> str:
        """ Register the receiver account to receive transfers for the new coin. """

        payload = {
            "type": "script_function_payload",
            "function": "0x1::managed_coin::mint",
            "type_arguments": [f"0x{account_coin_owner.address()}::{coin_type}Coin::{coin_type}Coin"],
            "arguments": [
                receiver_address,
                f"{amount}"
            ]
        }
        res = self.execute_transaction_with_payload(account_coin_owner, payload)
        return str(res["hash"])

    def get_balance(
        self,
        account_address: str,
        coin_type_address: str,
        coin_type: str,
    ) -> str:
        """ Returns the coin balance of the given account """

        balance = self.account_resource(account_address, f"0x1::coin::CoinStore<0x{coin_type_address}::{coin_type}Coin::{coin_type}Coin>")
        return balance["data"]["coin"]["value"]