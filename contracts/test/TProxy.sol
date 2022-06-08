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

import "./TIERC20.sol";

interface IPool {
    function getTokens() external view returns (address[] memory);
    function joinPoolForTxOrigin(uint256, uint256[] calldata) external;    
}

contract TProxy {

    // Join pool
    function proxyJoinPool(
        address poolAddress,
        uint256 poolAmountOut,
        uint256[] calldata maxAmountsIn
    )
    external {
        IPool pool = IPool(poolAddress);
        address[] memory tokensIn = pool.getTokens();

        // Getting the tokens from msg.sender and approving the pool 
        for(uint i = 0; i < tokensIn.length; i++) {
            bool transferFrom = TIERC20(tokensIn[i]).transferFrom(msg.sender, address(this), maxAmountsIn[i]);
            require(transferFrom, "ERR_ERC20");
            bool approve = TIERC20(tokensIn[i]).approve(poolAddress, type(uint).max);
            require(approve, "ERR_ERC20");
        }

        pool.joinPoolForTxOrigin(poolAmountOut, maxAmountsIn);

        // Sending any unused funds to msg.sender
        for(uint i = 0; i < tokensIn.length; i++) {
            bool transfer = TIERC20(tokensIn[i]).transfer(msg.sender, TIERC20(tokensIn[i]).balanceOf(address(this)));
            require(transfer, "ERR_ERC20");
        }

    }

}