// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.0;

import "../interfaces/IAggregatorV3.sol";


contract TConstantOracle is IAggregatorV3 {

    uint80 latestRoundId = 1;
    uint8 _decimals = 8;
    int256 _precision = 100000000;

    mapping(uint80 => int256) public prices;
    mapping(uint80 => uint256) public timestamps;

    constructor(int256 value) {
        prices[latestRoundId] = value;
        timestamps[latestRoundId] = 16000;

    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function description() public pure override returns (string memory) {
        return "Constant";
    }

    function version() public pure override returns (uint256) {
        return 1;
    }

    // getRoundData and latestRoundData should both raise "No data present"
    // if they do not have data to report, instead of returning unset values
    // which could be misinterpreted as actual reported values.
    function getRoundData(uint80 _roundId)
    public
    view
    override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        int256 a = prices[_roundId];
        uint256 ts = timestamps[_roundId];
        return (_roundId, a, ts, ts, _roundId);
    }
    function latestRoundData()
    public
    view
    override returns (
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) {
        int256 a = prices[latestRoundId];
        uint256 ts = timestamps[latestRoundId];
        return (latestRoundId, a, ts, ts, latestRoundId);
    }
}
