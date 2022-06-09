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

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
* @title Contains the external methods implemented by PoolToken
*/
interface IPoolToken is IERC20 {
    
    /**
    * @notice Returns token's name
    */
    function name() external pure returns (string memory name);

    /**
    * @notice Returns token's symbol
    */
    function symbol() external pure returns (string memory symbol);
    
    /**
    * @notice Returns token's decimals
    */
    function decimals() external pure returns(uint8 decimals);

    /**
    * @notice Increases an address approval by the input amount
    */
    function increaseApproval(address dst, uint256 amt) external returns (bool);

    /**
    * @notice Decreases an address approval by the input amount
    */
    function decreaseApproval(address dst, uint256 amt) external returns (bool);

}