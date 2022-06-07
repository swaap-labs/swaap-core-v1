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

import "../Math.sol";
import "../ChainlinkUtils.sol";
import "../structs/Struct.sol";

library TMathMMM {

    struct FormattedInput {
        Struct.TokenGlobal pivot;
        Struct.TokenGlobal[] others;
        Struct.JoinExitSwapParameters joinexitswapParameters;
        Struct.GBMParameters gbmParameters;
        Struct.HistoricalPricesParameters hpParameters;
    }

    function getLogSpreadFactor(
        int256 mean, uint256 variance,
        uint256 z, uint256 horizon
    )
    public pure
    returns (int256 x) {
        return Math.getLogSpreadFactor(mean, variance, horizon, z);
    }

    function getMMMWeight(
        uint256 tokenWeightOut,
        int256 mean, uint256 variance,
        uint256 z, uint256 horizon
    )    public pure
    returns (uint256 weight, uint256 spread)
    {
        Struct.GBMEstimation memory gbmEstimation = Struct.GBMEstimation(mean, variance, true);
        Struct.GBMParameters memory gbmParameters = Struct.GBMParameters(z, horizon);
        return Math.getMMMWeight(true, Const.FALLBACK_SPREAD, tokenWeightOut, gbmEstimation, gbmParameters);
    }

    function getTokenBalanceAtEquilibrium(
        uint256 tokenBalance1,
        uint256 tokenWeight1,
        uint256 tokenBalance2,
        uint256 tokenWeight2,
        uint256 relativePrice
    )
    public pure
    returns (uint256 balanceAtEquilibrium)
    {
        return balanceAtEquilibrium = Math.getTokenBalanceAtEquilibrium(
            tokenBalance1,
            tokenWeight1,
            tokenBalance2,
            tokenWeight2,
            relativePrice
        );
    }

    function calcAdaptiveFeeGivenInAndOut(
        uint256 tokenBalanceIn,
        uint256 tokenAmountIn,
        uint256 tokenWeightIn,
        uint256 tokenBalanceOut,
        uint256 tokenAmountOut,
        uint256 tokenWeightOut
    )
    public pure
    returns (uint256)
    {
        return Math.calcAdaptiveFeeGivenInAndOut(
            tokenBalanceIn,tokenAmountIn, tokenWeightIn,
            tokenBalanceOut, tokenAmountOut, tokenWeightOut
        );
    }

    function calcPoolOutGivenSingleInAdaptiveFees(
        uint256 poolValueInTokenIn,
        uint256 tokenBalanceIn,
        uint256 tokenWeightIn,
        uint256 tokenAmountIn
    )
    public pure
    returns (uint256)
    {
        return Math.calcPoolOutGivenSingleInAdaptiveFees(
            poolValueInTokenIn, tokenBalanceIn, tokenWeightIn, tokenAmountIn
        );
    }

    function calcSingleOutGivenPoolInAdaptiveFees(
        uint256 poolValueInTokenOut,
        uint256 tokenBalanceOut,
        uint256 normalizedTokenWeightOut,
        uint256 normalizedPoolAmountOut
    )
    public pure
    returns (uint256)
    {
        return Math.calcSingleOutGivenPoolInAdaptiveFees(
            poolValueInTokenOut, tokenBalanceOut, normalizedTokenWeightOut, normalizedPoolAmountOut
        );
    }

    function getOutTargetGivenIn(
        uint256 tokenBalanceOut, uint256 relativePrice, uint256 tokenAmountIn
    )
    public pure
    returns (uint256)
    {
        return tokenBalanceOut - Num.div(tokenAmountIn, relativePrice);
    }

    function getPoolTotalValue(
        address quoteAddress,
        uint256 quoteBalance,
        uint8 quoteDecimals, // sum of the decimals of the token and its oracle
        address[] memory basesAddress,
        uint256[] memory basesBalance,
        uint8[] memory basesDecimals // sum of the decimals of the token and its oracle
    ) public view returns (uint256) {
        Struct.TokenRecord memory quoteRecord = Struct.TokenRecord(quoteDecimals, quoteBalance, 0); // balance and weight are not used in getTotalValue
        Struct.LatestRound memory quoteLatestRound = ChainlinkUtils.getLatestRound(quoteAddress);
        Struct.TokenGlobal memory quote = Struct.TokenGlobal(quoteRecord, quoteLatestRound);
        Struct.TokenGlobal[] memory bases = new Struct.TokenGlobal[](basesAddress.length);
        for (uint i=0; i < basesAddress.length;) {
            Struct.LatestRound memory latestRound = ChainlinkUtils.getLatestRound(basesAddress[i]);
            Struct.TokenRecord memory info = Struct.TokenRecord(basesDecimals[0], basesBalance[i], 0); // weight is not used in getTotalValue
            Struct.TokenGlobal memory token = Struct.TokenGlobal(info, latestRound);
            bases[i] = token;
            unchecked { ++i; }
        }
        return Math.getPoolTotalValue(quote, bases);
    }

    function calcSingleOutGivenPoolInMMM(
        address pivotOracleAddress,
        uint256 pivotBalance,
        uint8 pivotDecimals, // sum of the decimals of the token and its oracle
        uint256 pivotWeight,
        address[] memory otherOracleAddresses,
        uint256[] memory otherBalances,
        uint8[]   memory otherDecimals, // sum of the decimals of the token and its oracle
        uint256[] memory otherWeights,
        uint256 amount,
        uint256 fee,
        uint256 fallbackSpread,
        uint256 poolSupply
    ) public view returns (uint256) {
        FormattedInput memory forrmattedInput = _formatInput(
            pivotOracleAddress,
            pivotBalance,
            pivotDecimals,
            pivotWeight,
            otherOracleAddresses,
            otherBalances,
            otherDecimals,
            otherWeights,
            amount,
            fee,
            fallbackSpread,
            poolSupply
        );
        return Math.calcSingleOutGivenPoolInMMM(
            forrmattedInput.pivot,
            forrmattedInput.others,
            forrmattedInput.joinexitswapParameters,
            forrmattedInput.gbmParameters,
            forrmattedInput.hpParameters
        );
    }

    function calcPoolOutGivenSingleInMMM(
        address pivotOracleAddress,
        uint256 pivotBalance,
        uint8 pivotDecimals, // sum of the decimals of the token and its oracle
        uint256 pivotWeight,
        address[] memory otherOracleAddresses,
        uint256[] memory otherBalances,
        uint8[]   memory otherDecimals, // sum of the decimals of the token and its oracle
        uint256[] memory otherWeights,
        uint256 amount,
        uint256 fee,
        uint256 fallbackSpread,
        uint256 poolSupply
    ) public view returns (uint256) {
        FormattedInput memory forrmattedInput = _formatInput(
            pivotOracleAddress,
            pivotBalance,
            pivotDecimals,
            pivotWeight,
            otherOracleAddresses,
            otherBalances,
            otherDecimals,
            otherWeights,
            amount,
            fee,
            fallbackSpread,
            poolSupply
        );
        return Math.calcPoolOutGivenSingleInMMM(
            forrmattedInput.pivot,
            forrmattedInput.others,
            forrmattedInput.joinexitswapParameters,
            forrmattedInput.gbmParameters,
            forrmattedInput.hpParameters
        );
    }

    function _formatInput(
        address pivotOracleAddress,
        uint256 pivotBalance,
        uint8 pivotDecimals, // sum of the decimals of the token and its oracle
        uint256 pivotWeight,
        address[] memory otherOracleAddresses,
        uint256[] memory otherBalances,
        uint8[]   memory otherDecimals, // sum of the decimals of the token and its oracle
        uint256[] memory otherWeights,
        uint256 amount,
        uint256 fee,
        uint256 fallbackSpread,
        uint256 poolSupply
    ) public view returns (FormattedInput memory formattedInput) {
        Struct.LatestRound memory pivotLatestRound = ChainlinkUtils.getLatestRound(pivotOracleAddress);
        Struct.TokenRecord memory pivotInfo = Struct.TokenRecord(pivotDecimals, pivotBalance, pivotWeight);
        formattedInput.pivot = Struct.TokenGlobal(pivotInfo, pivotLatestRound);
        formattedInput.others = new Struct.TokenGlobal[](otherOracleAddresses.length);
        for (uint i=0; i < otherOracleAddresses.length;) {
            Struct.LatestRound memory latestRound = ChainlinkUtils.getLatestRound(otherOracleAddresses[i]);
            Struct.TokenRecord memory info = Struct.TokenRecord(otherDecimals[i], otherBalances[i], otherWeights[i]);
            Struct.TokenGlobal memory other = Struct.TokenGlobal(info, latestRound);
            formattedInput.others[i] = other;
            unchecked { ++i; }
        }
        formattedInput.joinexitswapParameters = Struct.JoinExitSwapParameters(
            amount,
            fee,
            fallbackSpread,
            poolSupply
        );
        // the spread is not considered here
        formattedInput.gbmParameters = Struct.GBMParameters(
            0,
            0
        );
        formattedInput.hpParameters = Struct.HistoricalPricesParameters(
            10, 1000, block.timestamp, 1
        );
        return formattedInput;
    }

}
