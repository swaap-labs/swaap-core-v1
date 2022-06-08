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
* @title The interface for a Swaap V1 Pool Factory
*/
interface IFactory {
    
    /**
    * @notice Emitted when a controller creates a pool
    * @param caller The pool's creator
    * @param pool The created pool's address
    */
    event LOG_NEW_POOL(
        address indexed caller,
        address indexed pool
    );

    /**
    * @notice Emitted when a Swaap labs transfer is requested
    * @param from The current Swaap labs address
    * @param to The pending new Swaap labs address
    */
    event LOG_TRANSFER_REQUESTED(
        address indexed from,
        address indexed to
    );

    /**
    * @notice Emitted when a new address accepts the Swaap labs role
    * @param from The old Swaap labs address
    * @param to The new Swaap labs address
    */
    event LOG_NEW_SWAAPLABS(
        address indexed from,
        address indexed to
    );

    /*
    * @notice Create new pool with default parameters
    */
    function newPool() external returns (address);
    
    /**
    * @notice Returns if an address corresponds to a pool created by the factory
    */
    function isPool(address b) external view returns (bool);
    
    /**
    * @notice Returns swaap labs' address
    */
    function getSwaapLabs() external view returns (address);

    /**
    * @notice Allows an owner to begin transferring ownership to a new address,
    * pending.
    */
    function transferOwnership(address _to) external;

    /**
    * @notice Allows an ownership transfer to be completed by the recipient.
    */
    function acceptOwnership() external;
   
    /**
    * @notice Sends the exit fees accumulated to swaap labs
    */
    function collect(address erc20) external;

    /**
    * @notice Pause or unpause the factory's pools
    * @dev Pause disables most of the pools functionalities (swap, joinPool & joinswap)
    * and only allows for LPs to withdraw their funds
    */
    function setPause(bool paused) external;
    
    /**
    * @notice Reverts pools if the factory is paused
    * @dev This function is called by the pools whenever a swap or a joinPool is being made
    */
    function whenNotPaused() external view;

    /**
    * @notice Revoke factory control over a pool's parameters
    */
    function revokePoolFactoryControl(address pool) external;
    
    /**
    * @notice Sets a pool's swap fee
    */
    function setPoolSwapFee(address pool, uint256 swapFee) external;
    
    /**
    * @notice Sets a pool's dynamic coverage fees Z
    */
    function setPoolDynamicCoverageFeesZ(address pool, uint64 dynamicCoverageFeesZ) external;

    /**
    * @notice Sets a pool's dynamic coverage fees horizon
    */
    function setPoolDynamicCoverageFeesHorizon(address pool, uint256 dynamicCoverageFeesHorizon) external;

    /**
    * @notice Sets a pool's price statistics lookback in round
    */    
    function setPoolPriceStatisticsLookbackInRound(address pool, uint8 priceStatisticsLookbackInRound) external;

    /**
    * @notice Sets a pool's price statistics lookback in seconds
    */    
    function setPoolPriceStatisticsLookbackInSec(address pool, uint64 priceStatisticsLookbackInSec) external;

    /**
    * @notice Sets a pool's statistics lookback step in round
    */
    function setPoolPriceStatisticsLookbackStepInRound(address pool, uint8 priceStatisticsLookbackStepInRound) external;

    /**
    * @notice Sets a pool's maximum price unpeg ratio
    */
    function setPoolMaxPriceUnpegRatio(address pool, uint256 maxPriceUnpegRatio) external;

}