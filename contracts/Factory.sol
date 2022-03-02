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


contract Factory {

    event LOG_NEW_POOL(
        address indexed caller,
        address indexed pool
    );

    event LOG_SWAAPLABS(
        address indexed caller,
        address indexed swaaplabs
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
        Pool pool = new Pool();
        _isPool[address(pool)] = true;
        emit LOG_NEW_POOL(msg.sender, address(pool));
        pool.setController(msg.sender);
        return pool;
    }


    address private _swaaplabs;

    constructor() {
        _swaaplabs = msg.sender;
    }

    function getSwaapLabs()
        external view
        returns (address)
    {
        return _swaaplabs;
    }

    function setSwaapLabs(address b)
        external
    {
        require(msg.sender == _swaaplabs, "ERR_NOT_SWAAPLABS");
        emit LOG_SWAAPLABS(msg.sender, b);
        _swaaplabs = b;
    }

    function collect(Pool pool)
        external
    {
        require(msg.sender == _swaaplabs, "ERR_NOT_SWAAPLABS");
        uint256 collected = IERC20(pool).balanceOf(address(this));
        bool xfer = pool.transfer(_swaaplabs, collected);
        require(xfer, "ERR_ERC20_FAILED");
    }

}