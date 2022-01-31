// SPDX-License-Identifier: GPL-3.0-or-later
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General internal License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General internal License for more details.

// You should have received a copy of the GNU General internal License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.8.0;

import "./contracts/PoolToken.sol";
import "./CryticInterface.sol";


contract MyToken is PoolToken, CryticInterface {

    constructor(uint balance, address allowed) {
        // balance is the new totalSupply
        _totalSupply = balance;
        // each user receives 1/3 of the balance and sets 
        // the allowance of the allowed address.
        uint initialTotalSupply = balance;
        _balance[crytic_owner] = initialTotalSupply/3;
        _allowance[crytic_owner][allowed] = balance;
        _balance[crytic_user] = initialTotalSupply/3;
        _allowance[crytic_user][allowed] = balance;
        _balance[crytic_attacker] = initialTotalSupply/3;
        _allowance[crytic_attacker][allowed] = balance;
    }

}
