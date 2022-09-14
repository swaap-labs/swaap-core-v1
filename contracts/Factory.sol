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

// Builds new Pools, logging their addresses and providing `isPool(address) -> (bool)`

import "./Pool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IFactory.sol";
import "./Errors.sol";

contract Factory is IFactory {

    using SafeERC20 for IERC20; 

    function _onlySwaapLabs() private view {
        _require(msg.sender == _swaaplabs, Err.NOT_SWAAPLABS);
    }

    modifier _onlySwaapLabs_() {
        _onlySwaapLabs();
        _;
    }

    modifier _onlyPool_(address pool) {
        _require(_isPool[address(pool)], Err.NOT_POOL);
        _;
    }
    
    mapping(address=>bool) private _isPool;
    
    address private _pendingSwaaplabs;
    address private _swaaplabs;
    bool private _paused;
    uint64 immutable private _pauseWindow;

    constructor() {
        _swaaplabs = msg.sender;
        _pauseWindow = uint64(block.timestamp) + Const.PAUSE_WINDOW;
    }

    /**
    * @notice Create new pool with default parameters
    */
    function newPool()
    external
    returns (address)
    {
        _require(!_paused, Err.PAUSED_FACTORY);
        Pool pool = new Pool();
        _isPool[address(pool)] = true;
        emit LOG_NEW_POOL(msg.sender, address(pool));
        pool.setControllerAndTransfer(msg.sender);
        return address(pool);
    }
    
    /**
    * @notice Returns if an address corresponds to a pool created by the factory
    * @param b The pool's address
    */
    function isPool(address b)
    external view returns (bool)
    {
        return _isPool[b];
    }

    /**
    * @notice Returns swaap labs' address
    */
    function getSwaapLabs()
    external view
    returns (address)
    {
        return _swaaplabs;
    }

    /**
    * @notice Allows an owner to begin transferring ownership to a new address,
    * pending.
    * @param _to The new pending owner's address
    */
    function transferOwnership(address _to)
    external
    _onlySwaapLabs_
    {
        _pendingSwaaplabs = _to;

        emit LOG_TRANSFER_REQUESTED(msg.sender, _to);
    }

    /**
    * @notice Allows an ownership transfer to be completed by the recipient.
    */
    function acceptOwnership()
    external
    {
        _require(msg.sender == _pendingSwaaplabs, Err.NOT_PENDING_SWAAPLABS);

        address oldOwner = _swaaplabs;
        _swaaplabs = msg.sender;
        _pendingSwaaplabs = address(0);

        emit LOG_NEW_SWAAPLABS(oldOwner, msg.sender);
    }
   
    /**
    * @notice Sends the exit fees accumulated to swaap labs
    * @param erc20 The token's address
    */
    function collect(address erc20)
    external
    _onlySwaapLabs_
    {
        uint256 collected = IERC20(erc20).balanceOf(address(this));
        IERC20(erc20).safeTransfer(msg.sender, collected);
    }
    
    /**
    * @notice Pause the factory's pools
    * @dev Pause disables most of the pools functionalities (swap, joinPool & joinswap)
    * and only allows LPs to withdraw their funds
    */
    function pauseProtocol() 
    external
    _onlySwaapLabs_
    {
        _require(block.timestamp < _pauseWindow, Err.PAUSE_WINDOW_EXCEEDED);
        _paused = true;
    }

    /**
    * @notice Resume the factory's pools
    * @dev Unpausing re-enables all the pools functionalities
    */
    function resumeProtocol()
    external 
    _onlySwaapLabs_
    {
        _require(block.timestamp < _pauseWindow, Err.PAUSE_WINDOW_EXCEEDED);
        _paused = false;
    }

    /**
    * @notice Reverts pools if the factory is paused
    * @dev This function is called by the pools whenever a swap or a joinPool is being made
    */
    function whenNotPaused()
    external view {
        _require(!_paused, Err.PAUSED_FACTORY);
    }

    /**
    * @notice Revoke factory control over a pool's parameters
    * @param pool The pool's address
    */
    function revokePoolFactoryControl(address pool)
    external
    _onlySwaapLabs_
    _onlyPool_(pool)
    {
        Pool(pool).revokeFactoryControl();
    }

    /**
    * @notice Sets a pool's swap fee
    * @param pool The pool's address
    * @param swapFee The new pool's swapFee
    */
    function setPoolSwapFee(address pool, uint256 swapFee) 
    external
    _onlySwaapLabs_
    {
        Pool(pool).setSwapFee(swapFee);
    }
    
    /**
    * @notice Sets a pool's dynamic coverage fees Z
    * @param pool The pool's address
    * @param dynamicCoverageFeesZ The new dynamic coverage fees' Z parameter
    */
    function setPoolDynamicCoverageFeesZ(address pool, uint64 dynamicCoverageFeesZ)
    external
    _onlySwaapLabs_
    _onlyPool_(pool)
    {
        Pool(pool).setDynamicCoverageFeesZ(dynamicCoverageFeesZ);
    }

    /**
    * @notice Sets a pool's dynamic coverage fees horizon
    * @param pool The pool's address
    * @param dynamicCoverageFeesHorizon The new dynamic coverage fees' horizon parameter
    */
    function setPoolDynamicCoverageFeesHorizon(address pool, uint256 dynamicCoverageFeesHorizon)
    external 
    _onlySwaapLabs_
    _onlyPool_(pool)
    {
        Pool(pool).setDynamicCoverageFeesHorizon(dynamicCoverageFeesHorizon);
    }

    /**
    * @notice Sets a pool's price statistics lookback in round
    * @param pool The pool's address
    * @param priceStatisticsLookbackInRound The new price statistics maximum round lookback
    */
    function setPoolPriceStatisticsLookbackInRound(address pool, uint8 priceStatisticsLookbackInRound)
    external
    _onlySwaapLabs_
    _onlyPool_(pool)
    {
        Pool(pool).setPriceStatisticsLookbackInRound(priceStatisticsLookbackInRound);
    }

    /**
    * @notice Sets a pool's price statistics lookback in seconds
    * @param pool The pool's address
    * @param priceStatisticsLookbackInSec The new price statistics maximum lookback in seconds
    */    
    function setPoolPriceStatisticsLookbackInSec(address pool, uint64 priceStatisticsLookbackInSec)
    external
    _onlySwaapLabs_
    _onlyPool_(pool)
    {
        Pool(pool).setPriceStatisticsLookbackInSec(priceStatisticsLookbackInSec);
    }

    /**
    * @notice Sets a pool's statistics lookback step in round
    * @param pool The pool's address
    * @param priceStatisticsLookbackStepInRound The new price statistics lookback's step
    */
    function setPoolPriceStatisticsLookbackStepInRound(address pool, uint8 priceStatisticsLookbackStepInRound)
    external
    _onlySwaapLabs_
    _onlyPool_(pool)
    {
        Pool(pool).setPriceStatisticsLookbackStepInRound(priceStatisticsLookbackStepInRound);
    }

    /**
    * @notice Sets a pool's maximum price unpeg ratio
    * @param pool The pool's address
    * @param maxPriceUnpegRatio The new maximum allowed price unpeg ratio
    */
    function setPoolMaxPriceUnpegRatio(address pool, uint256 maxPriceUnpegRatio)
    external
    _onlySwaapLabs_
    _onlyPool_(pool)
    {
        Pool(pool).setMaxPriceUnpegRatio(maxPriceUnpegRatio);
    }

}