// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU Affero General Public License for more details.

// You should have received a copy of the GNU Affero General Public License
// along with this program. If not, see <http://www.gnu.org/licenses/>.

pragma solidity =0.8.12;

import "../interfaces/IAggregatorV3.sol";


contract TDAIOracle is IAggregatorV3 {

    uint256 private timestamp;

    uint80 private latestRoundId = 2009;
    uint8 private _decimals = 8;
    int256 private _precision = 100000000;

    mapping(uint80 => int256) public prices;
    mapping(uint80 => uint256) public timestamps;

    constructor() {

        timestamp = block.timestamp;

        prices[latestRoundId] = 99990575;
        timestamps[latestRoundId] = timestamp;

        prices[latestRoundId - 1] = 100000000;
        timestamps[latestRoundId - 1] = timestamp - 404;

        prices[latestRoundId - 2] = 100054178;
        timestamps[latestRoundId - 2] = timestamp - 86839;

        prices[latestRoundId - 3] = 100034433;
        timestamps[latestRoundId - 3] = timestamp - 173265;

        prices[latestRoundId - 4] = 100044915;
        timestamps[latestRoundId - 4] = timestamp - 259699;

        prices[latestRoundId - 5] = 100008103;
        timestamps[latestRoundId - 5] = timestamp - 346123;

        prices[latestRoundId - 6] = 99986759;
        timestamps[latestRoundId - 6] = timestamp - 432567;

        prices[latestRoundId - 7] = 100000000;
        timestamps[latestRoundId - 7] = timestamp - 518982;

        prices[latestRoundId - 8] = 100000000;
        timestamps[latestRoundId - 8] = timestamp - 605412;

        prices[latestRoundId - 9] = 100006444;
        timestamps[latestRoundId - 9] = timestamp - 705324;

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

    function updateTimestamp(uint256 timestamp_) public {
        timestamp = timestamp_;
    }

    function addDataPoint(int256 price_, uint256 timestamp_) public {
        latestRoundId++;
        prices[latestRoundId] = price_;
        timestamps[latestRoundId] = timestamp_;
    }

}
