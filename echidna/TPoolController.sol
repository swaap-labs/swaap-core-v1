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

import "./contracts/Pool.sol";
import "./CryticInterface.sol";


contract TPoolControllerPrivileged is CryticInterface, Pool {

    function echidna_controller_should_change() public returns (bool) {
        if (this.getController() == crytic_owner) {
            setController(crytic_user);
            return (this.getController() == crytic_user);
        }
        // if the controller was changed, this should return true
        return true;
    }

    function echidna_revert_controller_cannot_be_null() public returns (bool) {
        if (this.getController() == crytic_owner) {
           // setting the controller to 0x0 should fail
           setController(address(0x0));
           return true;
        }
        // if the controller was changed, this should revert anyway
        revert();
    }
}

contract TPoolControllerUnprivileged is CryticInterface, Pool {

    function echidna_no_other_user_can_change_the_controller() public view returns (bool) {
        // the controller cannot be changed by other users
        return this.getController() == crytic_owner;
    }

}
