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

import "./interfaces/IPoolHelpers/IPoolToken.sol";
import "./Errors.sol";

// Highly opinionated token implementation

contract PoolToken is IPoolToken {

    mapping(address => uint256)                   internal _balance;
    mapping(address => mapping(address=>uint256)) internal _allowance;
    uint256 internal _totalSupply;

    function _mint(uint256 amt) internal {
        _balance[address(this)] = _balance[address(this)] + amt;
        _totalSupply = _totalSupply + amt;
        emit Transfer(address(0), address(this), amt);
    }

    function _burn(uint256 amt) internal {
        _balance[address(this)] = _balance[address(this)] - amt;
        _totalSupply = _totalSupply - amt;
        emit Transfer(address(this), address(0), amt);
    }

    function _move(address src, address dst, uint256 amt) internal {
        _require(dst != address(0), Err.NULL_ADDRESS);
        
        uint256 fromBalance = _balance[src];
        _require(fromBalance >= amt, Err.INSUFFICIENT_BALANCE);
        unchecked {
            _balance[src] = fromBalance - amt;
        }
        _balance[dst] += amt;

        emit Transfer(src, dst, amt);
    }

    function _push(address to, uint256 amt) internal {
        _move(address(this), to, amt);
    }

    function _pull(address from, uint256 amt) internal {
        _move(from, address(this), amt);
    }

    string constant private _name     = "Swaap Pool Token";
    string constant private _symbol   = "SPT";
    uint8  constant private _decimals = 18;

    function name() external pure returns (string memory) {
        return _name;
    }

    function symbol() external pure returns (string memory) {
        return _symbol;
    }

    function decimals() external pure returns(uint8) {
        return _decimals;
    }


    function allowance(address src, address dst) external view returns (uint256) {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) external view returns (uint256) {
        return _balance[whom];
    }

    function totalSupply() public view returns (uint256) {
        return _totalSupply;
    }

    function approve(address dst, uint256 amt) external returns (bool) {
        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function increaseApproval(address dst, uint256 amt) external returns (bool) {
        _allowance[msg.sender][dst] = _allowance[msg.sender][dst] + amt;
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function decreaseApproval(address dst, uint256 amt) external returns (bool) {
        uint256 oldValue = _allowance[msg.sender][dst];
        if (amt > oldValue) {
            _allowance[msg.sender][dst] = 0;
        } else {
            _allowance[msg.sender][dst] = oldValue - amt;
        }
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function transfer(address dst, uint256 amt) external returns (bool) {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(address src, address dst, uint256 amt) external returns (bool) {
        if (msg.sender != src && _allowance[src][msg.sender] != type(uint256).max) {
            uint256 currentAllowance = _allowance[src][msg.sender];
            _require(currentAllowance >= amt, Err.INSUFFICIENT_ALLOWANCE);
            unchecked {
                _allowance[src][msg.sender] = currentAllowance - amt;
            }
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        _move(src, dst, amt);
        return true;
    }
}