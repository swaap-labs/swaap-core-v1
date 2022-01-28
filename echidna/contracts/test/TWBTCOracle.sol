// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity =0.8.0;

import "./TIAggregatorV3.sol";


contract TWBTCOracle is TIAggregatorV3 {

    uint80 latestRoundId = 2021;
    uint8 _decimals = 8;
    int256 _precision = 100000000;

    mapping(uint80 => int256) public prices;
    mapping(uint80 => uint256) public timestamps;

    constructor() {
        prices[latestRoundId] = 4201340255103;
        timestamps[latestRoundId] = 1641891047;

        prices[latestRoundId - 1] = 4245514000000;
        timestamps[latestRoundId - 1] = 1641889577;

        prices[latestRoundId - 2] = 4197967571800;
        timestamps[latestRoundId - 2] = 1641864920;

        prices[latestRoundId - 3] = 4155911000000;
        timestamps[latestRoundId - 3] = 1641840072;

        prices[latestRoundId - 4] = 4114025628407;
        timestamps[latestRoundId - 4] = 1641837070;

        prices[latestRoundId - 5] = 4072208879420;
        timestamps[latestRoundId - 5] = 1641836334;

        prices[latestRoundId - 6] = 4126856799512;
        timestamps[latestRoundId - 6] = 1641835899;

        prices[latestRoundId - 7] = 4172855909572;
        timestamps[latestRoundId - 7] = 1641831698;

        prices[latestRoundId - 8] = 4100152514691;
        timestamps[latestRoundId - 8] = 1641826417;

        prices[latestRoundId - 9] = 4059125000000;
        timestamps[latestRoundId - 9] = 1641826072;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function description() public pure override returns (string memory) {
        return "WBTC";
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
