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

import "./TIAggregatorV3.sol";


contract TOracle is TIAggregatorV3 {

    uint80 latestRoundId;
    uint8 _decimals;
    int256 _precision = 10;

    mapping(uint80 => int256) public prices;
    mapping(uint80 => uint256) public timestamps;

    constructor(int256[] memory prices_, uint256[] memory avjc_, uint8 decimals_, uint80 roundId_) {
        _decimals = decimals_;
        latestRoundId = roundId_;
        for (uint8 i=0; i < avjc_.length; i++) {
            prices[latestRoundId - i] = prices_[i];
            timestamps[latestRoundId - i] = avjc_[i];
        }
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
        uint256 ts = block.timestamp - timestamps[_roundId];
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
        uint256 ts = block.timestamp - timestamps[latestRoundId];
        return (latestRoundId, a, ts, ts, latestRoundId);
    }

}
