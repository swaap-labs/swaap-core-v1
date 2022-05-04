// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity =0.8.12;

import "./interfaces/IAggregatorV3.sol";
import "./structs/Struct.sol";
import "./Const.sol";
import "./Num.sol";


library ChainlinkUtils {

    /**
    * @notice Retrieves the latest price from the given oracle price feed
    * @dev We consider the token price to be > 0
    * @param oracle The price feed oracle
    * @return The latest price
    */
    function getTokenLatestPrice(address oracle) internal view returns (uint256) {
        (, int256 latestPrice, , ,) = IAggregatorV3(oracle).latestRoundData();
        require(latestPrice > 0, "16");
        return uint256(latestPrice); // we consider the token price to be > 0
    }

    function getLatestRound(address oracle) internal view returns (Struct.LatestRound memory) {
        (uint80 latestRoundId, int256 latestPrice, , uint256 latestTimestamp,) = IAggregatorV3(oracle).latestRoundData();
        require(latestPrice > 0, "16");
        return Struct.LatestRound(
            oracle,
            latestRoundId,
            latestPrice,
            latestTimestamp
        );
    }

    /**
    * @notice Retrieves historical data from round id.
    * @dev Will not fail and return (0, 0) if no data can be found.
    * @param oracle The price feed oracle
    * @param _roundId The the round of interest ID
    * @return The round price
    * @return The round timestamp
    */
    function getRoundData(address oracle, uint80 _roundId) internal view returns (int256, uint256) {
        try IAggregatorV3(oracle).getRoundData(_roundId) returns (
            uint80 ,
            int256 _price,
            uint256 ,
            uint256 _timestamp,
            uint80
        ) {
            return (_price, _timestamp);
        } catch {}
        return (0, 0);
    }


    /**
    * @notice Computes the price of token 2 in terms of token 1
    * @param latestRound_1 The latest oracle data for token 1
    * @param latestRound_2 The latest oracle data for token 2
    * @return The last price of token 2 divded by the last price of token 1
    */
    function getTokenRelativePrice(
        Struct.LatestRound memory latestRound_1, Struct.LatestRound memory latestRound_2
    )
    internal
    view
    returns (uint256) {
        return _getTokenRelativePrice(
            latestRound_1.price, IAggregatorV3(latestRound_1.oracle).decimals(),
            latestRound_2.price, IAggregatorV3(latestRound_2.oracle).decimals()
        );
    }

    function _getTokenRelativePrice(
        int256 price_1, uint8 decimal_1,
        int256 price_2, uint8 decimal_2
    )
    internal
    pure
    returns (uint256) {
        // we consider tokens price to be > 0
        uint256 rawDiv = Num.bdiv(Num.positivePart(price_2), Num.positivePart(price_1));
        if (decimal_1 == decimal_2) {
            return rawDiv;
        } else if (decimal_1 > decimal_2) {
            return Num.bmul(
                rawDiv,
                10**(decimal_1 - decimal_2)*Const.BONE
            );
        } else {
            return Num.bdiv(
                rawDiv,
                10**(decimal_2 - decimal_1)*Const.BONE
            );
        }
    }

    /**
    * @notice Computes the previous price of tokenIn in terms of tokenOut 's upper bound
    * @param oracle_1 The token_1 oracle's address
    * @param roundId_1 The latest token_1 oracle update's roundId
    * @param price_1 The latest token_1 oracle update's price
    * @param timestamp_1 The latest token_1 oracle update's timestamp
    * @param oracle_2 The token_2 oracle's address
    * @param roundId_2 The latest token_2 oracle update's roundId
    * @param price_2 The latest token_2 oracle update's price
    * @param timestamp_2 The latest token_2 oracle update's timestamp
    * @return The ratio of token 2 and token 1 values if well defined, else 0
    */
    function getMaxRelativePriceInLastBlock(
        address oracle_1,
        uint80 roundId_1,
        int256 price_1,
        uint256 timestamp_1,
        address oracle_2,
        uint80 roundId_2,
        int256 price_2,
        uint256 timestamp_2
    ) internal view returns (uint256) {
        {
            int256 temp_price_1 = price_1;
            while (timestamp_1 == block.timestamp) {
                --roundId_1;
                (temp_price_1, timestamp_1) = ChainlinkUtils.getRoundData(
                    oracle_1, roundId_1
                );
                if (temp_price_1 == 0) {
                    return 0;
                }
                if (temp_price_1 < price_1) {
                    price_1 = temp_price_1;
                }
            }
        }
        {
            int256 temp_price_2 = price_2;
            while (timestamp_2 == block.timestamp) {
                --roundId_2;
                (temp_price_2, timestamp_2) = ChainlinkUtils.getRoundData(
                    oracle_2, roundId_2
                );
                if (temp_price_2 == 0) {
                    return 0;
                }
                if (temp_price_2 > price_2) {
                    price_2 = temp_price_2;
                }
            }
        }

        return _getTokenRelativePrice(
            price_1, IAggregatorV3(oracle_1).decimals(),
            price_2, IAggregatorV3(oracle_2).decimals()
        );
    }

}