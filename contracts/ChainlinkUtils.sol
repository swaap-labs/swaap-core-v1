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
import "./structs/Struct.sol";
import "./Const.sol";
import "./Num.sol";
import "./Errors.sol";

library ChainlinkUtils {

    /**
    * @notice Retrieves the oracle latest price, its decimals and description
    * @dev We consider the token price to be > 0
    * @param oracle The price feed oracle's address
    * @return The latest price's value
    * @return The latest price's number of decimals
    * @return The oracle description
    */
    function getTokenLatestPrice(address oracle) internal view returns (uint256, uint8, string memory) {
        AggregatorV3Interface feed = AggregatorV3Interface(oracle);
        (, int256 latestPrice, , uint256 latestTimestamp,) = feed.latestRoundData();
        // we assume that block.timestamp >= latestTimestamp, else => revert
        _require(block.timestamp - latestTimestamp <= Const.ORACLE_TIMEOUT, Err.EXCEEDED_ORACLE_TIMEOUT);
        _require(latestPrice > 0, Err.NON_POSITIVE_PRICE);
        return (uint256(latestPrice), feed.decimals(), feed.description()); // we consider the token price to be > 0
    }

    function getLatestRound(address oracle) internal view returns (Struct.LatestRound memory) {
        (
            uint80 latestRoundId, int256 latestPrice, , uint256 latestTimestamp,
        ) = AggregatorV3Interface(oracle).latestRoundData();
        // we assume that block.timestamp >= latestTimestamp, else => revert
        _require(block.timestamp - latestTimestamp <= Const.ORACLE_TIMEOUT, Err.EXCEEDED_ORACLE_TIMEOUT);
        _require(latestPrice > 0, Err.NON_POSITIVE_PRICE);
        return Struct.LatestRound(
            oracle,
            latestRoundId,
            uint256(latestPrice),
            latestTimestamp
        );
    }

    /**
    * @notice Retrieves historical data from round id.
    * @dev Special cases:
    * - if retrieved price is negative --> fails
    * - if no data can be found --> returns (0,0)
    * @param oracle The price feed oracle
    * @param _roundId The the round of interest ID
    * @return The round price
    * @return The round timestamp
    */
    function getRoundData(address oracle, uint80 _roundId) internal view returns (uint256, uint256) {
        try AggregatorV3Interface(oracle).getRoundData(_roundId) returns (
            uint80 ,
            int256 _price,
            uint256 ,
            uint256 _timestamp,
            uint80
        ) {
            _require(_price >= 0, Err.NEGATIVE_PRICE);
            return (uint256(_price), _timestamp);
        } catch {}
        return (0, 0);
    }


    /**
    * @notice Computes the price of token 2 in terms of token 1
    * @param price_1 The latest price data for token 1
    * @param decimals_1 The sum of the decimals of token 1 its oracle
    * @param price_2 The latest price data for token 2
    * @param decimals_2 The sum of the decimals of token 2 its oracle
    * @return The last price of token 2 divded by the last price of token 1
    */
    function getTokenRelativePrice(
        uint256 price_1, uint8 decimals_1,
        uint256 price_2, uint8 decimals_2
    )
    internal
    pure
    returns (uint256) {
        // we consider tokens price to be > 0
        if (decimals_1 > decimals_2) {
            return Num.div(
                Num.mul(price_2, (10**(decimals_1 - decimals_2))*Const.ONE),
                price_1
            );
        } else if (decimals_1 < decimals_2) {
            return Num.div(
                Num.div(price_2, price_1),
                (10**(decimals_2 - decimals_1))*Const.ONE
            );
        } else { // decimals_1 == decimals_2
            return Num.div(price_2, price_1);
         }
    }

    /**
    * @notice Computes the previous price of tokenIn in terms of tokenOut 's upper bound
    * @param latestRound_1 The token_1's latest round
    * @param decimals_1 The sum of the decimals of token 1 its oracle 
    * @param latestRound_2 The token_2's latest round
    * @param decimals_2 The sum of the decimals of token 2 its oracle
    * @return The ratio of token 2 and token 1 values if well defined, else 0
    */
    function getMaxRelativePriceInLastBlock(
        Struct.LatestRound memory latestRound_1,
        uint8 decimals_1,
        Struct.LatestRound memory latestRound_2,
        uint8 decimals_2
    ) internal view returns (uint256) {
        
        uint256 minPrice_1 = latestRound_1.price;
        {
            uint256 timestamp_1  = latestRound_1.timestamp;
            uint256 temp_price_1;
            uint80  roundId_1    = latestRound_1.roundId;
            address oracle_1     = latestRound_1.oracle;

            while (timestamp_1 == block.timestamp) {
                --roundId_1;
                (temp_price_1, timestamp_1) = ChainlinkUtils.getRoundData(
                    oracle_1, roundId_1
                );
                if (temp_price_1 == 0) {
                    return 0;
                }
                if (temp_price_1 < minPrice_1) {
                    minPrice_1 = temp_price_1;
                }
            }
        }

        uint maxPrice_2 = latestRound_2.price;
        {
            uint256 timestamp_2  = latestRound_2.timestamp;
            uint256 temp_price_2;
            uint80  roundId_2    = latestRound_2.roundId;
            address oracle_2     = latestRound_2.oracle;

            while (timestamp_2 == block.timestamp) {
                --roundId_2;
                (temp_price_2, timestamp_2) = ChainlinkUtils.getRoundData(
                    oracle_2, roundId_2
                );
                if (temp_price_2 == 0) {
                    return 0;
                }
                if (temp_price_2 > maxPrice_2) {
                    maxPrice_2 = temp_price_2;
                }
            }
        }

        return getTokenRelativePrice(
            minPrice_1, decimals_1,
            maxPrice_2, decimals_2
        );
    }

}