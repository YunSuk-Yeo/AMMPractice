from typing import Optional, Tuple
from transaction import Account, RestClient

class CoinSwap(RestClient):
    def initialize_coin_swap(
        self, 
        account_from: Account, 
        coin_type_address: str, 
        amount_a: str, 
        amount_b: str) -> Optional[str]:
        """ Initialize a coin swap for the pair of (CoinA, CoinB). """
        payload = {
            "type": "script_function_payload",
            "function": f"0x{account_from.address()}::CoinSwap::initialize",
            "type_arguments": [
                f"0x{coin_type_address}::CoinA::CoinA", 
                f"0x{coin_type_address}::CoinB::CoinB", 
                f"0x{coin_type_address}::CoinLP::CoinLP",
            ],
            "arguments": [
                amount_a,
                amount_b,
            ]
        }

        res = self.execute_transaction_with_payload(account_from, payload)
        return str(res["hash"])

    def get_pool_info(
        self,
        account_address: str,
        coin_type_address: str,
    ) -> Tuple[str, str]:
        """ Returns the pool info of the given pair """

        pool_info = self.account_resource(account_address, f"0x{account_address}::CoinSwap::PoolStore<0x{coin_type_address}::CoinA::CoinA, 0x{coin_type_address}::CoinB::CoinB>")
        return (str(pool_info["data"]["coin_a"]["value"]), str(pool_info["data"]["coin_b"]["value"]))

    def swap(
        self,
        account_from: Account, 
        coin_type_address: str,
        amount_offer: str,
        minimum_receive: str,
        is_reverse: bool,
    ) -> Optional[str]:
        """ Swap offer coin to ask coin """

        payload = {
            "type": "script_function_payload",
            "function": f"0x{account_from.address()}::CoinSwap::swap",
            "type_arguments": [
                f"0x{coin_type_address}::CoinA::CoinA", 
                f"0x{coin_type_address}::CoinB::CoinB", 
            ],
            "arguments": [
                account_from.address(),
                amount_offer,
                minimum_receive,
                is_reverse,
            ]
        }

        res = self.execute_transaction_with_payload(account_from, payload)
        return str(res["hash"])