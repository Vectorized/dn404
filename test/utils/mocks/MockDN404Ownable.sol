// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./MockDN404.sol";
import {Ownable} from "solady/auth/Ownable.sol";

contract MockDN404Ownable is MockDN404, Ownable {
    constructor() {
        _initializeOwner(msg.sender);
    }
}
