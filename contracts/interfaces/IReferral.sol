// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IReferral {
    function set(address from, address to) external;

    function refOf(address to) external view returns (address);
}
