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
    * @notice Retrieves historical data from round id.
    * @dev Will not fail and return (0, 0) if no data can be found.
    * @param priceFeed The oracle of interest
    * @param _roundId The the round of interest ID
    * @return The round price
    * @return The round timestamp
    */
    function getRoundData(IAggregatorV3 priceFeed, uint80 _roundId) internal view returns (int256, uint256) {
        try priceFeed.getRoundData(_roundId) returns (
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
    * @notice Computes the price of token 1 in terms of token 2
    * @param latestRound_1 The latest oracle data for token 1
    * @param latestRound_2 The latest oracle data for token 2
    * @return The price of token 2 in terms of token 1
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
        uint256 rawDiv = Num.bdiv(Num.abs(price_2), Num.abs(price_1));
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
    * @notice Computes the previous price of tokenIn in terms of tokenOut
    * @dev previous price correspond to price at lastRoundId - 1
    * @param latestRoundIn The latest oracle data for tokenIn
    * @param latestRoundOut The latest oracle data for tokenIn
    * @return The price of token 2 in terms of token 1
    */
    function getPreviousPrice(
        Struct.LatestRound memory latestRoundIn,
        Struct.LatestRound memory latestRoundOut
    ) internal view returns (uint256) {

        IAggregatorV3 oracleIn = IAggregatorV3(latestRoundIn.oracle);
        (int256 priceIn, uint256 tsIn) = ChainlinkUtils.getRoundData(
            oracleIn, latestRoundIn.roundId - 1
        );
        IAggregatorV3 oracleOut = IAggregatorV3(latestRoundOut.oracle);
        (int256 priceOut, uint256 tsOut)  = ChainlinkUtils.getRoundData(
            oracleOut, latestRoundOut.roundId - 1
        );
        return _getPreviousPrice(
            priceIn, tsIn, oracleIn.decimals(), latestRoundIn.price,
            priceOut, tsOut, oracleOut.decimals(), latestRoundOut.price
        );

    }

    function _getPreviousPrice(
        int256 priceIn, uint256 tsIn, uint8 decimalsIn, int256 newPriceIn,
        int256 priceOut, uint256 tsOut, uint8 decimalsOut, int256 newPriceOut
    ) internal pure returns (uint256) {
        if (tsIn > tsOut) {
            return _getTokenRelativePrice(
                priceIn, decimalsIn,
                newPriceOut, decimalsOut
            );
        } else if (tsIn < tsOut) {
            return _getTokenRelativePrice(
                newPriceIn, decimalsIn,
                priceOut, decimalsOut
            );
        } else {
            return _getTokenRelativePrice(
                priceIn, decimalsIn,
                priceOut, decimalsOut
            );
        }
    }

}