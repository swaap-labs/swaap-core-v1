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

import "@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";


contract TWETHOracle is AggregatorV3Interface {

    uint256 private timestamp;

    uint80 private latestRoundId = 2018;
    uint8 private _decimals = 8;
    int256 private _precision = 100000000;

    mapping(uint80 => int256) public prices;
    mapping(uint80 => uint256) public timestamps;

    constructor() {

        timestamp = block.timestamp;

        prices[latestRoundId] = 312882040500;
        timestamps[latestRoundId] = timestamp;

        prices[latestRoundId - 1] = 311613433829;
        timestamps[latestRoundId - 1] = timestamp - 3063;

        prices[latestRoundId - 2] = 311445000000;
        timestamps[latestRoundId - 2] = timestamp - 6695;

        prices[latestRoundId - 3] = 310672718218;
        timestamps[latestRoundId - 3] = timestamp - 10329;

        prices[latestRoundId - 4] = 311461368677;
        timestamps[latestRoundId - 4] = timestamp - 13960;

        prices[latestRoundId - 5] = 311394849384;
        timestamps[latestRoundId - 5] = timestamp - 17591;

        prices[latestRoundId - 6] = 311964523049;
        timestamps[latestRoundId - 6] = timestamp - 21222;

        prices[latestRoundId - 7] = 308857000000;
        timestamps[latestRoundId - 7] = timestamp - 24854;

        prices[latestRoundId - 8] = 306919151091;
        timestamps[latestRoundId - 8] = timestamp - 26639;

        prices[latestRoundId - 9] = 308571414036;
        timestamps[latestRoundId - 9] = timestamp - 30271;

    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function description() public pure override returns (string memory) {
        return "WETH";
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
