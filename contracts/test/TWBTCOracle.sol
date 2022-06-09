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


contract TWBTCOracle is IAggregatorV3 {

    uint256 private timestamp;

    uint80 private latestRoundId = 2021;
    uint8 private _decimals = 8;
    int256 private _precision = 100000000;

    mapping(uint80 => int256) public prices;
    mapping(uint80 => uint256) public timestamps;

    constructor() {

        timestamp = block.timestamp;

        prices[latestRoundId] = 4201340255103;
        timestamps[latestRoundId] = timestamp;

        prices[latestRoundId - 1] = 4245514000000;
        timestamps[latestRoundId - 1] = timestamp - 1953;

        prices[latestRoundId - 2] = 4197967571800;
        timestamps[latestRoundId - 2] = timestamp - 3423;

        prices[latestRoundId - 3] = 4155911000000;
        timestamps[latestRoundId - 3] = timestamp - 28080;

        prices[latestRoundId - 4] = 4114025628407;
        timestamps[latestRoundId - 4] = timestamp - 52928;

        prices[latestRoundId - 5] = 4072208879420;
        timestamps[latestRoundId - 5] = timestamp - 55930;

        prices[latestRoundId - 6] = 4126856799512;
        timestamps[latestRoundId - 6] = timestamp - 56666;

        prices[latestRoundId - 7] = 4172855909572;
        timestamps[latestRoundId - 7] = timestamp - 57101;

        prices[latestRoundId - 8] = 4100152514691;
        timestamps[latestRoundId - 8] = timestamp - 61302;

        prices[latestRoundId - 9] = 4059125000000;
        timestamps[latestRoundId - 9] = timestamp - 66583;

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

    function updateTimestamp(uint256 timestamp_) public {
        timestamp = timestamp_;
    }

    function addDataPoint(int256 price_, uint256 timestamp_) public {
        latestRoundId++;
        prices[latestRoundId] = price_;
        timestamps[latestRoundId] = timestamp_;
    }

}
