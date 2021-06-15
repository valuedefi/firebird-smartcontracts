// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

import "@openzeppelin/contracts-ethereum-package/contracts/access/Ownable.sol";

import "../interfaces/ICappedMintableBurnableERC20.sol";

contract VbswapToHopePearlBridge is OwnableUpgradeSafe {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    address public vbswap;
    address public pearl;

    uint256 public startReleaseTime;
    uint256 public totalBurned;
    uint256 public totalMinted;

    uint256 public initialMigrationRate;
    uint256 public weeklyHalvingRate;

    event Migrate(address indexed account, uint256 vbswapAmount, uint256 pearlAmount);

    function initialize(address _vbswap, address _pearl, uint256 _startReleaseTime, uint256 _initialMigrationRate, uint256 _weeklyHalvingRate) public initializer {
        OwnableUpgradeSafe.__Ownable_init();
        vbswap = _vbswap;
        pearl = _pearl;
        startReleaseTime = _startReleaseTime;
        initialMigrationRate = _initialMigrationRate;
        weeklyHalvingRate = _weeklyHalvingRate;
    }

    function passedWeeks() public view returns (uint256) {
        uint256 _startReleaseTime = startReleaseTime;
        if (now < startReleaseTime) return 0;
        return now.sub(_startReleaseTime).div(7 days);
    }

    function migrateRate() public view returns (uint256) {
        uint256 _weeks = passedWeeks();
        if (_weeks == 0) return initialMigrationRate;
        uint256 _totalHalvingRate = _weeks.mul(weeklyHalvingRate);
        return (initialMigrationRate <= _totalHalvingRate) ? 0 : initialMigrationRate.sub(_totalHalvingRate);
    }

    function migrate(uint256 _vbswapAmount) external {
        require(now >= startReleaseTime, "migration not opened yet");
        uint256 _rate = migrateRate();
        require(_rate > 0, "zero rate");
        IERC20(vbswap).transferFrom(_msgSender(), address(this), _vbswapAmount);
        ICappedMintableBurnableERC20(vbswap).burn(_vbswapAmount);
        uint256 _mintAmount = _vbswapAmount.mul(_rate).div(10000);
        ICappedMintableBurnableERC20(pearl).mint(_msgSender(), _mintAmount);
        totalBurned = totalBurned.add(_vbswapAmount);
        totalMinted = totalMinted.add(_mintAmount);
        emit Migrate(_msgSender(), _vbswapAmount, _mintAmount);
    }

    function setStartReleaseTime(uint256 _startReleaseTime) external onlyOwner {
        require(_startReleaseTime > startReleaseTime, "cant set _startReleaseTime to lower value");
        startReleaseTime = _startReleaseTime;
    }

    function setWeeklyHalvingRate(uint256 _weeklyHalvingRate) external onlyOwner {
        require(initialMigrationRate.div(_weeklyHalvingRate) >= 5, "too high"); // <= 20%
        weeklyHalvingRate = _weeklyHalvingRate;
    }

    // This function allows governance to take unsupported tokens out of the contract. This is in an effort to make someone whole, should they seriously mess up.
    // There is no guarantee governance will vote to return these. It also allows for removal of airdropped tokens.
    function governanceRecoverUnsupported(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeTransfer(_to, _amount);
    }
}
