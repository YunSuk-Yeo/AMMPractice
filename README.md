## Move Language Practice Repo
This project is test repository for Move Language. It's mimicking UniswapV2 style constant product AMM.

### How to test
```shell
aptos move test
```

### How to run
1. Run local testnet Initialize aptos account
```sh
# run local testnet
aptos node run-local-testnet --with-faucet --force-restart

# initialize account
aptos init
```

2. Change `rest_url` and `faucet_url` to local of `./.aptos/config.yaml`
```sh
    rest_url: "http://0.0.0.0:8080"
    faucet_url: "http://0.0.0.0:8081"
```

3. Publish modules
```sh
aptos move publish --named-addresses AMMPractice={"account of ./.aptos/config.yaml"}
```

4. Copy `private_key` from `./.aptos/config.yaml` to `./examples/.env`
```sh
# without 0x prefix
SEED="c31d55d9fd922e633e60b7be70d3aabf92eb881822607b7ec0451ae7d469d504"
```

5. Run python test script
```sh
pip3 install -r requirements.txt
python3 ./main.py
```