// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is disstributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity =0.8.12;

// Builds new Pools, logging their addresses and providing `isPool(address) -> (bool)`

import "./Pool.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IPausedFactory.sol";

contract Factory is IPausedFactory {

    using SafeERC20 for IERC20; 

    event LOG_NEW_POOL(
        address indexed caller,
        address indexed pool
    );

    event LOG_TRANSFER_REQUESTED(
        address indexed from,
        address indexed to
    );
    event LOG_NEW_SWAAPLABS(
        address indexed from,
        address indexed to
    );

    mapping(address=>bool) private _isPool;

    function isPool(address b)
    external view returns (bool)
    {
        return _isPool[b];
    }

    function newPool()
    external
    returns (Pool)
    {
        require(!_paused, "36");
        Pool pool = new Pool();
        _isPool[address(pool)] = true;
        emit LOG_NEW_POOL(msg.sender, address(pool));
        pool.setController(msg.sender);
        return pool;
    }

    address private _pendingSwaaplabs;
    address private _swaaplabs;
    bool private _paused;
    uint64 immutable private _setPauseWindow;

    constructor() {
        _swaaplabs = msg.sender;
        _setPauseWindow = uint64(block.timestamp) + Const.PAUSE_WINDOW;
    }

    function getSwaapLabs()
        external view
        returns (address)
    {
        return _swaaplabs;
    }

    /**
    * @notice Allows an owner to begin transferring ownership to a new address,
    * pending.
    */
    function transferOwnership(address _to)
        external
    {
        require(msg.sender == _swaaplabs, "34");
        _pendingSwaaplabs = _to;

        emit LOG_TRANSFER_REQUESTED(msg.sender, _to);
    }

    /**
    * @notice Allows an ownership transfer to be completed by the recipient.
    */
    function acceptOwnership()
        external
    {
        require(msg.sender == _pendingSwaaplabs, "20");

        address oldOwner = _swaaplabs;
        _swaaplabs = msg.sender;
        _pendingSwaaplabs = address(0);

        emit LOG_NEW_SWAAPLABS(oldOwner, msg.sender);
    }
   
    function collect(address erc20)
        external
    {
        require(msg.sender == _swaaplabs, "34");
        uint256 collected = IERC20(erc20).balanceOf(address(this));
        IERC20(erc20).safeTransfer(msg.sender, collected);
    }

    function setPause(bool paused) external {
        require(msg.sender == _swaaplabs, "34");
        require(block.timestamp < _setPauseWindow, "45");
        _paused = paused;
    }

    function whenNotPaused() external view {
        require(!_paused, "36");
    }

}