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
    * @param controller The new controller's address
    */
    function setControllerAndTransfer(address controller) external;
    
    /**
    * @notice Allows a controller to begin transferring ownership to a new address
    * @dev The function will revert if there are binded tokens in an un-finalized pool
    * This prevents any accidental loss of funds for the current controller
    * @param pendingController The newly suggested controller 
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
    * @param publicSwap The new publicSwap's state
    */
    function setPublicSwap(bool publicSwap) external;

    /**
    * @notice Enables publicswap and finalizes the pool's parameters (tokens, balances, oracles...)
    */
    function finalize() external;
    
    /** 
    * @notice Sets swap fee
    * @param swapFee The new swap fee
    */
    function setSwapFee(uint256 swapFee) external;
    
    /**
    * @notice Sets dynamic coverage fees Z
    * @param dynamicCoverageFeesZ The new dynamic coverage fees' Z parameter
    */
    function setDynamicCoverageFeesZ(uint64 dynamicCoverageFeesZ) external;
    
    /**
    * @notice Sets dynamic coverage fees horizon
    * @param dynamicCoverageFeesHorizon The new dynamic coverage fees' horizon parameter
    */
    function setDynamicCoverageFeesHorizon(uint256 dynamicCoverageFeesHorizon) external;
    
    /**
    * @notice Sets price statistics maximum lookback in round
    * @param priceStatisticsLookbackInRound The new price statistics maximum round lookback
    */
    function setPriceStatisticsLookbackInRound(uint8 priceStatisticsLookbackInRound) external;
    
    /**
    * @notice Sets price statistics lookback step in round
    * @param priceStatisticsLookbackStepInRound The new price statistics lookback's step
    */
    function setPriceStatisticsLookbackStepInRound(uint8 priceStatisticsLookbackStepInRound) external;
    
    /** 
    * @notice Sets price statistics maximum lookback in seconds
    * @param priceStatisticsLookbackInSec The new price statistics maximum lookback in seconds
    */
    function setPriceStatisticsLookbackInSec(uint256 priceStatisticsLookbackInSec) external;

    /**
    * @notice Sets price statistics maximum unpeg ratio
    * @param maxPriceUnpegRatio The new maximum allowed price unpeg ratio
    */
    function setMaxPriceUnpegRatio(uint256 maxPriceUnpegRatio) external;
}