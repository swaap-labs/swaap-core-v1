from web3 import Web3
import json
import os

config = {
    "mainnet": {
        "ETH": "0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419",
        "BTC": "0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c",
        "DAI": "0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9",
    },
    "kovan": {
        "ETH": "0x9326BFA02ADD2366b30bacB125260Af641031331",
        "BTC": "0x6135b13325bfC4B00278B4abC5e20bbce2D6580e",
        "DAI": "0x777A68032a88E5A84678A77Af2CD65A7b3c0775a",
    },
    "rinkeby": {
        "ETH": "0x8A753747A1Fa494EC906cE90E9f37563A8AF630e",
        "BTC": "0xECe365B379E1dD183B20fc5f022230C044d51404",
        "DAI": "0x2bA49Aaa16E6afD2a993473cfB70Fa8559B523cF",
    },
    "polygon-mainnet": {
        "ETH": "0xF9680D99D6C9589e2a93a78A04A279e509205945",
        "BTC": "0xc907E116054Ad103354f2D350FD2514433D57F6f",
        "DAI": "0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D",
    }
}

API = os.environ.get("API_TEMPLATE")

def main(
        chain_name="mainnet",
        num_rounds=10,
):
    web3 = Web3(
        Web3.HTTPProvider(
            API
        )
    )

    abi = '[{"inputs":[],"name":"decimals","outputs":[{"internalType":"uint8","name":"","type":"uint8"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"description","outputs":[{"internalType":"string","name":"","type":"string"}],"stateMutability":"view","type":"function"},{"inputs":[{"internalType":"uint80","name":"_round_id","type":"uint80"}],"name":"getRoundData","outputs":[{"internalType":"uint80","name":"round_id","type":"uint80"},{"internalType":"int256","name":"answer","type":"int256"},{"internalType":"uint256","name":"startedAt","type":"uint256"},{"internalType":"uint256","name":"updatedAt","type":"uint256"},{"internalType":"uint80","name":"answeredInRound","type":"uint80"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"latestRoundData","outputs":[{"internalType":"uint80","name":"round_id","type":"uint80"},{"internalType":"int256","name":"answer","type":"int256"},{"internalType":"uint256","name":"startedAt","type":"uint256"},{"internalType":"uint256","name":"updatedAt","type":"uint256"},{"internalType":"uint80","name":"answeredInRound","type":"uint80"}],"stateMutability":"view","type":"function"},{"inputs":[],"name":"version","outputs":[{"internalType":"uint256","name":"","type":"uint256"}],"stateMutability":"view","type":"function"}]'

    raw_data = {}
    for token in config[chain_name]:
        contract = web3.eth.contract(address=config[chain_name][token], abi=abi)

        latest_data = contract.functions.latestRoundData().call()
        print(latest_data)
        raw_data[token] = {
            "oracle": config[chain_name][token],
            "data": [
                {
                    "round_id": str(latest_data[0]),
                    "price": str(latest_data[1]),
                    "timestamp": str(latest_data[3]),
                }
            ]
        }
        counter = 1
        round_id = latest_data[0] - 1
        while True:
            historical_data = contract.functions.getRoundData(round_id).call()
            print(historical_data)
            round_id -= 1
            raw_data[token]["data"].append({
                "round_id": str(historical_data[0]),
                "price": str(historical_data[1]),
                "timestamp": str(historical_data[3]),
            })
            counter += 1
            if counter >= num_rounds:
                break

    with open("test/data.json", "w") as f:
        json.dump(raw_data, f)


if __name__ == "__main__":
    main()