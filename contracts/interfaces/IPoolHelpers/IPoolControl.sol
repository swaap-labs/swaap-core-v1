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
* @title Contains the useful methods to a pool controller
*/
interface IPoolControl {

    /**
    * @notice Revokes factory control over pool parameters
    * @dev Factory control can only be revoked by the factory and not the pool controller
    */
    function revokeFactoryControl() external;

    /**
    * @notice Gives back factory control over the pool parameters
    */
    function giveFactoryControl() external;
    
    /**
    * @notice Allows a controller to transfer ownership to a new address
    * @dev It is recommended to use transferOwnership/acceptOwnership logic for safer transfers
    * to avoid any faulty input
    * This function is useful when creating pools using a proxy contract and transfer pool assets
    * WARNING: Binded assets are also transferred to the new controller if the pool is not finalized
    */  
    function setControllerAndTransfer(address controller) external;
    
    /**
    * @notice Allows a controller to begin transferring ownership to a new address
    * @dev The function will revert if there are binded tokens in an un-finalized pool
    * This prevents any accidental loss of funds for the current controller
    */
    function transferOwnership(address pendingController) external;
    
    /**
    * @notice Allows a controller transfer to be completed by the recipient
    */
    function acceptOwnership() external;
    
    /**
    * @notice Bind a new token to the pool
    * @param token The token's address
    * @param balance The token's balance
    * @param denorm The token's weight
    * @param priceFeedAddress The token's Chainlink price feed
    */
    function bindMMM(address token, uint256 balance, uint80 denorm, address priceFeedAddress) external;
    
    /**
    * @notice Replace a binded token's balance, weight and price feed's address
    * @param token The token's address
    * @param balance The token's balance
    * @param denorm The token's weight
    * @param priceFeedAddress The token's Chainlink price feed
    */
    function rebindMMM(address token, uint256 balance, uint80 denorm, address priceFeedAddress) external;
    
    /**
    * @notice Unbind a token from the pool
    * @dev The function will return the token's balance back to the controller
    * @param token The token's address
    */
    function unbindMMM(address token) external;
    
    /**
    * @notice Enables public swaps on the pool but does not finalize the parameters
    * @dev Unfinalized pool enables exclusively the controller to add liquidity into the pool
    */
    function setPublicSwap(bool publicSwap) external;

    /**
    * @notice Enables publicswap and finalizes the pool's tokens, price feeds, initial shares, balances and weights
    */
    function finalize() external;
    
    /** 
    * @notice Sets swap fee
    */
    function setSwapFee(uint256 swapFee) external;
    
    /**
    * @notice Sets dynamic coverage fees Z
    */
    function setDynamicCoverageFeesZ(uint64 dynamicCoverageFeesZ) external;
    
    /**
    * @notice Sets dynamic coverage fees horizon
    */
    function setDynamicCoverageFeesHorizon(uint256 dynamicCoverageFeesHorizon) external;
    
    /**
    * @notice Sets price statistics maximum lookback in round
    */
    function setPriceStatisticsLookbackInRound(uint8 priceStatisticsLookbackInRound) external;
    
    /** 
    * @notice Sets price statistics maximum lookback in seconds
    */
    function setPriceStatisticsLookbackStepInRound(uint8 priceStatisticsLookbackStepInRound) external;
    
    /**
    * @notice Sets price statistics lookback step in round
    * @dev This corresponds to the roundId lookback step when looking for historical prices
    */
    function setPriceStatisticsLookbackInSec(uint256 priceStatisticsLookbackInSec) external;

    /**
    * @notice Sets price statistics maximum unpeg ratio
    */
    function setMaxPriceUnpegRatio(uint256 maxPriceUnpegRatio) external;
}