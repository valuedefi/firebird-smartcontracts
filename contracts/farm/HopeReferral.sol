// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../interfaces/IReferral.sol";

contract HopeReferral is OwnableUpgradeSafe, IReferral {
    uint256 public constant BLOCKS_PER_DAY = 38000;

    mapping(address => address) public referral;
    mapping(address => bool) public authorities;
    mapping(address => address[]) public referralOf;

    event Affiliate(address indexed referrer, address indexed referee);

    modifier isAuthorised() {
        require(authorities[msg.sender], "!authorised");
        _;
    }

    function initialize() public initializer {
        OwnableUpgradeSafe.__Ownable_init();
    }

    function addAuthority(address authority) external onlyOwner {
        authorities[authority] = true;
    }

    function removeAuthority(address authority) external onlyOwner {
        authorities[authority] = false;
    }

    function set(address from, address to) external override isAuthorised {
        if (
            from != address(0x0) &&
            to != address(0x0) &&
            from != to &&
            referral[to] == address(0x0)
        ) {
            referral[to] = from;
            referralOf[from].push(to);
            emit Affiliate(from, to);
        }
    }

    function refOf(address to) public view override returns (address) {
        return referral[to];
    }

    function numberReferralOf(address add) external view returns (uint256) {
        return referralOf[add].length;
    }
}
