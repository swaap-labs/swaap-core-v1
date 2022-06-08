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

/**
* @title Contains the useful methods to get the Pool's parameters and state
*/
interface IPoolState{
    
    /**
    * @dev Returns true if a trader can swap on the pool
    */
    function isPublicSwap() external view returns (bool);

    /**
    * @dev Returns true if a liquidity provider can join the pool
    * A trader can swap on the pool if the pool is either finalized or isPublicSwap
    */
    function isFinalized() external view returns (bool);

    /**
    * @dev Returns true if the token is binded to the pool
    */
    function isBound(address t) external view returns (bool);

    /**
    * @dev Returns the binded tokens
    */
    function getTokens() external view returns (address[] memory tokens);
    
    /**
    * @dev Returns the initial weight of a binded token
    * The initial weight is the un-adjusted weight set by the controller at bind
    * The adjusted weight is the corrected weight based on the token's price performance:
    * adjusted_weight = initial_weight * current_price / initial_price
    */
    function getDenormalizedWeight(address token) external view returns (uint256);
    
    /**
    * @dev Returns the balance of a binded token
    */
    function getBalance(address token) external view returns (uint256);
    
    /**
    * @dev Returns the swap fee of the pool
    */
    function getSwapFee() external view returns (uint256);
    
    /**
    * @dev Returns the current controller of the pool
    */
    function getController() external view returns (address);
    
    /**
    * @dev Returns the coverage parameters of the pool
    */
    function getCoverageParameters() external view returns (
        uint8   priceStatisticsLBInRound,
        uint8   priceStatisticsLBStepInRound,
        uint64  dynamicCoverageFeesZ,
        uint256 dynamicCoverageFeesHorizon,
        uint256 priceStatisticsLBInSec,
        uint256 maxPriceUnpegRatio
    );

    /**
    * @dev Returns the token's price when it was binded to the pool
    */
    function getTokenOracleInitialPrice(address token) external view returns (uint256);

    /**
    * @dev Returns the oracle's address of a token
    */
    function getTokenPriceOracle(address token) external view returns (address);


}