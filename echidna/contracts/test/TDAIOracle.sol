// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.0;

import "./TIAggregatorV3.sol";


contract TDAIOracle is TIAggregatorV3 {

    uint80 latestRoundId = 2009;
    uint8 _decimals = 8;
    int256 _precision = 100000000;

    mapping(uint80 => int256) public prices;
    mapping(uint80 => uint256) public timestamps;

    constructor() {
        prices[latestRoundId] = 99990575;
        timestamps[latestRoundId] = 1641892596;

        prices[latestRoundId - 1] = 100000000;
        timestamps[latestRoundId - 1] = 1641806161;

        prices[latestRoundId - 2] = 100054178;
        timestamps[latestRoundId - 2] = 1641719735;

        prices[latestRoundId - 3] = 100034433;
        timestamps[latestRoundId - 3] = 1641633301;

        prices[latestRoundId - 4] = 100044915;
        timestamps[latestRoundId - 4] = 1641546877;

        prices[latestRoundId - 5] = 100008103;
        timestamps[latestRoundId - 5] = 1641460433;

        prices[latestRoundId - 6] = 99986759;
        timestamps[latestRoundId - 6] = 1641374018;

        prices[latestRoundId - 7] = 100000000;
        timestamps[latestRoundId - 7] = 1641287588;

        prices[latestRoundId - 8] = 100000000;
        timestamps[latestRoundId - 8] = 1641187676;

        prices[latestRoundId - 9] = 100006444;
        timestamps[latestRoundId - 9] = 1641101258;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function description() public pure override returns (string memory) {
        return "DAI";
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
