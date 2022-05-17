// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.12;

import "./TIAggregatorV3.sol";


contract TConstantOracle is TIAggregatorV3 {

    uint256 timestamp;

    uint80 latestRoundId = 1;
    uint8 _decimals = 8;
    int256 _precision = 100000000;

    mapping(uint80 => int256) public prices;
    mapping(uint80 => uint256) public timestamps;

    constructor(int256 value_) {
        timestamp = block.timestamp;
        prices[latestRoundId] = value_;
        timestamps[latestRoundId] = timestamp;
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

    function updateTimestamp(uint256 timestamp_) public {
        timestamp = timestamp_;
    }

    function addDataPoint(int256 price_, uint256 timestamp_) public {
        latestRoundId++;
        prices[latestRoundId] = price_;
        timestamps[latestRoundId] = timestamp_;
    }

}
