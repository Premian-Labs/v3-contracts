// SPDX-License-Identifier: UNLICENSED

pragma solidity >=0.8.19;

import {Test} from "forge-std/Test.sol";
import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";
import {IERC20} from "@solidstate/contracts/interfaces/IERC20.sol";
import {IERC20Metadata} from "@solidstate/contracts/token/ERC20/metadata/IERC20Metadata.sol";
import {SafeCast} from "@solidstate/contracts/utils/SafeCast.sol";

import {ONE} from "contracts/libraries/Constants.sol";
import {OptionMath} from "contracts/libraries/OptionMath.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";
import {ERC20Mock} from "contracts/test/ERC20Mock.sol";

import {IMiningPool} from "contracts/mining/MiningPool.sol";
import {IPriceRepository} from "contracts/mining/IPriceRepository.sol";
import {MiningPool} from "contracts/mining/MiningPool.sol";
import {MiningPoolFactory} from "contracts/mining/MiningPoolFactory.sol";
import {PriceRepository} from "contracts/mining/PriceRepository.sol";
import {PriceRepositoryProxy} from "contracts/mining/PriceRepositoryProxy.sol";

import {Assertions} from "../Assertions.sol";

contract MiningPoolTest is Assertions, Test {
    using SafeCast for int256;
    using SafeCast for uint256;

    PriceRepository priceRepository;

    MiningPool premiaUSDCMiningPool;
    MiningPool wbtcUSDCMiningPool;
    MiningPool premiaWETHMiningPool;

    Users users;

    address premia;
    address weth;
    address wbtc;
    address usdc;

    Data[3] _data;

    struct Data {
        UD60x18 discount;
        UD60x18 spot;
        UD60x18 settlementITM;
        UD60x18 penalty;
        uint256 expiryDuration;
        uint256 exerciseDuration;
        uint256 lockupDuration;
    }

    struct Users {
        address underwriter;
        address longReceiver;
        address keeper;
    }

    function setUp() public {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );

        uint256 fork = vm.createFork(ETH_RPC_URL, 17101000); // Apr-22-2023 09:30:23 AM +UTC
        vm.selectFork(fork);

        users = Users({underwriter: vm.addr(1), longReceiver: vm.addr(2), keeper: vm.addr(3)});

        PriceRepository implementation = new PriceRepository();
        PriceRepositoryProxy proxy = new PriceRepositoryProxy(address(implementation), users.keeper);
        priceRepository = PriceRepository(address(proxy));

        MiningPool miningPoolImplementation = new MiningPool();
        ProxyUpgradeableOwnable miningPoolProxy = new ProxyUpgradeableOwnable(address(miningPoolImplementation));

        MiningPoolFactory miningPoolFactory = new MiningPoolFactory(address(miningPoolProxy));

        _data[0] = Data(ud(0.55e18), ud(1e18), ud(2e18), ud(0.80e18), 30 days, 30 days, 365 days);
        _data[1] = Data(ud(0.1e18), ud(30000e18), ud(35000e18), ud(0.20e18), 60 days, 90 days, 30 days);
        _data[2] = Data(ud(0.90e18), ud(0.0005e18), ud(0.01e18), ud(1e18), 180 days, 11 days, 365 days);

        premia = 0x6399C842dD2bE3dE30BF99Bc7D1bBF6Fa3650E70; // PREMIA (18 decimals)
        weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // PREMIA (18 decimals)
        wbtc = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599; // WBTC (8 decimals)
        usdc = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48; // USDC (6 decimals)

        premiaUSDCMiningPool = MiningPool(
            miningPoolFactory.deployMiningPool(
                premia,
                usdc,
                users.underwriter,
                address(priceRepository),
                // TODO: deploy payment splitter
                address(1),
                _data[0].discount,
                _data[0].penalty,
                _data[0].expiryDuration,
                _data[0].exerciseDuration,
                _data[0].lockupDuration
            )
        );

        wbtcUSDCMiningPool = MiningPool(
            miningPoolFactory.deployMiningPool(
                wbtc,
                usdc,
                users.underwriter,
                address(priceRepository),
                // TODO: deploy payment splitter
                address(1),
                _data[1].discount,
                _data[1].penalty,
                _data[1].expiryDuration,
                _data[1].exerciseDuration,
                _data[1].lockupDuration
            )
        );

        premiaWETHMiningPool = MiningPool(
            miningPoolFactory.deployMiningPool(
                premia,
                weth,
                users.underwriter,
                address(priceRepository),
                // TODO: deploy payment splitter
                address(1),
                _data[2].discount,
                _data[2].penalty,
                _data[2].expiryDuration,
                _data[2].exerciseDuration,
                _data[2].lockupDuration
            )
        );
    }

    function getMaturity(uint256 timestamp, uint256 expiryDuration) internal pure returns (uint256 maturity) {
        maturity = timestamp - (timestamp % 24 hours) + 8 hours + expiryDuration;
    }

    function setPriceAt(uint256 timestamp, UD60x18 price, address base, address quote) internal {
        vm.prank(users.keeper);
        priceRepository.setPriceAt(base, quote, timestamp, price);
    }

    function scaleDecimalsFrom(address token, uint256 amount) internal view returns (UD60x18) {
        uint8 decimals = IERC20Metadata(token).decimals();
        return ud(OptionMath.scaleDecimals(amount, decimals, 18));
    }

    function scaleDecimalsTo(address token, UD60x18 amount) internal view returns (uint256) {
        uint8 decimals = IERC20Metadata(token).decimals();
        return OptionMath.scaleDecimals(amount.unwrap(), 18, decimals);
    }

    function _test_writeFrom_Success(
        Data memory data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal returns (uint64 maturity, uint256 collateral, uint256 longTokenId, uint256 shortTokenId) {
        maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));
        setPriceAt(block.timestamp, data.spot, base, quote);

        UD60x18 _size = ud(size);
        collateral = scaleDecimalsTo(base, _size);
        deal(base, users.underwriter, collateral);

        vm.startPrank(users.underwriter);
        IERC20(base).approve(address(miningPool), collateral);
        miningPool.writeFrom(users.longReceiver, _size);
        vm.stopPrank();

        UD60x18 strike = data.discount * data.spot;
        longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);
        shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, strike);

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), size);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), collateral);
    }

    function test_writeFrom_Success() public {
        _test_writeFrom_Success(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_writeFrom_Success(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    event WriteFrom(
        address indexed underwriter,
        address indexed longReceiver,
        UD60x18 contractSize,
        UD60x18 strike,
        uint64 maturity
    );

    function test_writeFrom_CorrectMaturity() public {
        setPriceAt(block.timestamp, ONE, premia, usdc);

        uint256 collateral = scaleDecimalsTo(premia, ud(100e18));
        deal(premia, users.underwriter, collateral);

        vm.prank(users.underwriter);
        IERC20(premia).approve(address(premiaUSDCMiningPool), collateral);

        UD60x18 size = ONE;

        // block.timestamp = Apr-22-2023 09:30:23 AM +UTC
        uint64 timeToMaturity = uint64(30 days);
        uint64 timestamp8AMUTC = 1682150400; // Apr-22-2023 08:00:00 AM +UTC
        uint64 expectedMaturity = timestamp8AMUTC + timeToMaturity; // May-22-2023 08:00:00 AM +UTC

        vm.expectEmit();
        emit WriteFrom(users.underwriter, users.longReceiver, size, ud(0.55e18), expectedMaturity);

        vm.prank(users.underwriter);
        premiaUSDCMiningPool.writeFrom(users.longReceiver, size);

        vm.warp(1682207999); // Apr-22-2023 23:59:59 PM +UTC

        expectedMaturity = timestamp8AMUTC + timeToMaturity; // May-22-2023 08:00:00 AM +UTC
        vm.expectEmit();
        emit WriteFrom(users.underwriter, users.longReceiver, size, ud(0.55e18), expectedMaturity);

        vm.prank(users.underwriter);
        premiaUSDCMiningPool.writeFrom(users.longReceiver, size);

        vm.warp(1682208000); // Apr-23-2023 00:00:00 PM +UTC

        timestamp8AMUTC = 1682236800; // Apr-23-2023 08:00:00 AM +UTC
        expectedMaturity = timestamp8AMUTC + timeToMaturity; // May-23-2023 08:00:00 AM +UTC
        vm.expectEmit();
        emit WriteFrom(users.underwriter, users.longReceiver, size, ud(0.55e18), expectedMaturity);

        vm.prank(users.underwriter);
        premiaUSDCMiningPool.writeFrom(users.longReceiver, size);
    }

    function test_writeFrom_RevertIf_UnderwriterNotAuthorized() public {
        vm.expectRevert(
            abi.encodeWithSelector(IMiningPool.MiningPool__UnderwriterNotAuthorized.selector, users.longReceiver)
        );

        vm.prank(users.longReceiver);
        premiaUSDCMiningPool.writeFrom(users.longReceiver, ud(1000000e18));
    }

    function _test_exercise_PhysicallySettled_Success(
        Data memory data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        (uint64 maturity, uint256 collateral, uint256 longTokenId, uint256 shortTokenId) = _test_writeFrom_Success(
            data,
            miningPool,
            size,
            base,
            quote
        );

        vm.warp(maturity);
        setPriceAt(maturity, data.settlementITM, base, quote);

        UD60x18 _strike = data.discount * data.spot;
        UD60x18 _size = ud(size);

        vm.startPrank(users.longReceiver);
        uint256 exerciseCost = scaleDecimalsTo(quote, (_size * _strike));
        deal(quote, users.longReceiver, exerciseCost);

        assertEq(IERC20(quote).balanceOf(address(users.longReceiver)), exerciseCost);

        IERC20(quote).approve(address(miningPool), exerciseCost);
        miningPool.exercise(longTokenId, _size);
        vm.stopPrank();

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), 0);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(quote).balanceOf(address(users.longReceiver)), 0);
        assertEq(IERC20(quote).balanceOf(address(users.underwriter)), 0);

        // TODO: assertEq(IERC20(quote).balanceOf(address(vxPREMIA)), 0.9e18 * exerciseCost);
        // TODO: assertEq(IERC20(quote).balanceOf(address(TREASURY)), 0.1e18 * exerciseCost);

        assertEq(IERC20(base).balanceOf(address(users.longReceiver)), collateral);
        assertEq(IERC20(base).balanceOf(address(users.underwriter)), 0);
        assertEq(IERC20(base).balanceOf(address(miningPool)), 0);
    }

    function test_exercise_PhysicallySettled_Success() public {
        _test_exercise_PhysicallySettled_Success(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_exercise_PhysicallySettled_Success(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function _test_exercise_CashSettled_Success(
        Data memory data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        (uint64 maturity, uint256 collateral, uint256 longTokenId, uint256 shortTokenId) = _test_writeFrom_Success(
            data,
            miningPool,
            size,
            base,
            quote
        );

        vm.warp(maturity);
        setPriceAt(maturity, data.settlementITM, base, quote);

        {
            uint256 lockupStart = maturity + data.exerciseDuration;
            uint256 lockupEnd = lockupStart + data.lockupDuration;
            vm.warp(lockupEnd);
        }

        uint256 exerciseValue;
        {
            UD60x18 intrinsicValue = data.settlementITM - data.discount * data.spot;
            UD60x18 _exerciseValue = (ud(size) * intrinsicValue) / data.settlementITM;
            _exerciseValue = _exerciseValue * (ONE - data.penalty);
            exerciseValue = scaleDecimalsTo(base, _exerciseValue);
        }

        vm.prank(users.longReceiver);
        miningPool.exercise(longTokenId, ud(size));

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), 0);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), size);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(quote).balanceOf(address(users.longReceiver)), 0);
        assertEq(IERC20(quote).balanceOf(address(users.underwriter)), 0);

        // TODO: assertEq(IERC20(quote).balanceOf(address(vxPREMIA)), 0);
        // TODO: assertEq(IERC20(quote).balanceOf(address(TREASURY)), 0);

        assertEq(IERC20(base).balanceOf(address(users.longReceiver)), exerciseValue);
        assertApproxEqAbs(IERC20(base).balanceOf(address(users.underwriter)), collateral - exerciseValue, 1); // handles rounding error of 1 wei
        assertApproxEqAbs(IERC20(base).balanceOf(address(miningPool)), 0, 1); // handles rounding error of 1 wei
    }

    function test_exercise_CashSettled_Success() public {
        _test_exercise_CashSettled_Success(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_exercise_CashSettled_Success(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function _test_exercise_RevertIf_TokenTypeNotLong(Data memory data, MiningPool miningPool) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));

        UD60x18 strike = data.discount * data.spot;
        uint256 shortTokenId = miningPool.formatTokenId(IMiningPool.TokenType.SHORT, maturity, strike);

        vm.expectRevert(IMiningPool.MiningPool__TokenTypeNotLong.selector);
        vm.prank(users.longReceiver);
        miningPool.exercise(shortTokenId, ud(1000000e18));
    }

    function test_exercise_RevertIf_TokenTypeNotLong() public {
        _test_exercise_RevertIf_TokenTypeNotLong(_data[0], premiaUSDCMiningPool);
        _test_exercise_RevertIf_TokenTypeNotLong(_data[1], wbtcUSDCMiningPool);
    }

    function _test_exercise_RevertIf_OptionNotExpired(Data memory data, MiningPool miningPool) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));

        UD60x18 strike = data.discount * data.spot;
        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);

        vm.expectRevert(abi.encodeWithSelector(IMiningPool.MiningPool__OptionNotExpired.selector, maturity));
        vm.warp(maturity - 1);
        vm.prank(users.longReceiver);
        miningPool.exercise(longTokenId, ud(1000000e18));
    }

    function test_exercise_RevertIf_OptionNotExpired() public {
        _test_exercise_RevertIf_OptionNotExpired(_data[0], premiaUSDCMiningPool);
        _test_exercise_RevertIf_OptionNotExpired(_data[1], wbtcUSDCMiningPool);
    }

    function _test_exercise_RevertIf_OptionOutTheMoney(
        Data memory data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        (uint64 maturity, , uint256 longTokenId, ) = _test_writeFrom_Success(data, miningPool, size, base, quote);

        UD60x18 _strike = data.discount * data.spot;
        UD60x18 settlementOTM = _strike.sub(ud(1));

        vm.warp(maturity);
        setPriceAt(maturity, settlementOTM, base, quote);

        vm.expectRevert(
            abi.encodeWithSelector(IMiningPool.MiningPool__OptionOutTheMoney.selector, settlementOTM, _strike)
        );

        vm.prank(users.longReceiver);
        miningPool.exercise(longTokenId, ud(size));
    }

    function test_exercise_RevertIf_OptionOutTheMoney() public {
        _test_exercise_RevertIf_OptionOutTheMoney(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_exercise_RevertIf_OptionOutTheMoney(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function _test_exercise_RevertIf_LockupNotExpired(
        Data memory data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) internal {
        (uint64 maturity, , uint256 longTokenId, ) = _test_writeFrom_Success(data, miningPool, size, base, quote);

        vm.warp(maturity);
        setPriceAt(maturity, data.settlementITM, base, quote);

        uint256 lockupStart = maturity + data.exerciseDuration;
        uint256 lockupEnd = lockupStart + data.lockupDuration;

        vm.warp(lockupStart);

        vm.expectRevert(
            abi.encodeWithSelector(IMiningPool.MiningPool__LockupNotExpired.selector, lockupStart, lockupEnd)
        );

        vm.prank(users.longReceiver);
        miningPool.exercise(longTokenId, ud(size));
    }

    function test_exercise_RevertIf_LockupNotExpired() public {
        _test_exercise_RevertIf_LockupNotExpired(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_exercise_RevertIf_LockupNotExpired(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function _test_settle_Success(
        Data memory data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) public {
        (uint64 maturity, uint256 collateral, uint256 longTokenId, uint256 shortTokenId) = _test_writeFrom_Success(
            data,
            miningPool,
            size,
            base,
            quote
        );

        UD60x18 _strike = data.discount * data.spot;
        UD60x18 settlementOTM = _strike.sub(ud(1));

        vm.warp(maturity);
        setPriceAt(maturity, settlementOTM, base, quote);

        vm.prank(users.underwriter);
        miningPool.settle(shortTokenId, ud(size));

        assertEq(miningPool.balanceOf(users.longReceiver, longTokenId), size);
        assertEq(miningPool.balanceOf(users.longReceiver, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, shortTokenId), 0);
        assertEq(miningPool.balanceOf(users.underwriter, longTokenId), 0);

        assertEq(IERC20(quote).balanceOf(address(users.longReceiver)), 0);
        assertEq(IERC20(quote).balanceOf(address(users.underwriter)), 0);

        // TODO: assertEq(IERC20(quote).balanceOf(address(vxPREMIA)), 0);
        // TODO: assertEq(IERC20(quote).balanceOf(address(TREASURY)), 0);

        assertEq(IERC20(base).balanceOf(address(users.longReceiver)), 0);
        assertEq(IERC20(base).balanceOf(address(users.underwriter)), collateral);
        assertEq(IERC20(base).balanceOf(address(miningPool)), 0);
    }

    function test_settle_Success() public {
        _test_settle_Success(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_settle_Success(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function _test_settle_RevertIf_TokenTypeNotShort(Data memory data, MiningPool miningPool) internal {
        uint64 maturity = uint64(getMaturity(block.timestamp, data.expiryDuration));

        UD60x18 strike = data.discount * data.spot;
        uint256 longTokenId = miningPool.formatTokenId(IMiningPool.TokenType.LONG, maturity, strike);

        vm.expectRevert(IMiningPool.MiningPool__TokenTypeNotShort.selector);

        vm.prank(users.underwriter);
        miningPool.settle(longTokenId, ud(1000000e18));
    }

    function test_settle_RevertIf_TokenTypeNotShort() public {
        _test_settle_RevertIf_TokenTypeNotShort(_data[0], premiaUSDCMiningPool);
        _test_settle_RevertIf_TokenTypeNotShort(_data[1], wbtcUSDCMiningPool);
    }

    function _test_settle_RevertIf_OptionNotExpired(
        Data memory data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) public {
        (uint64 maturity, , , uint256 shortTokenId) = _test_writeFrom_Success(data, miningPool, size, base, quote);

        vm.expectRevert(abi.encodeWithSelector(IMiningPool.MiningPool__OptionNotExpired.selector, maturity));

        vm.prank(users.underwriter);
        miningPool.settle(shortTokenId, ud(size));
    }

    function test_settle_RevertIf_OptionNotExpired() public {
        _test_settle_RevertIf_OptionNotExpired(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_settle_RevertIf_OptionNotExpired(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }

    function _test_settle_RevertIf_OptionInTheMoney(
        Data memory data,
        MiningPool miningPool,
        uint256 size,
        address base,
        address quote
    ) public {
        (uint64 maturity, , , uint256 shortTokenId) = _test_writeFrom_Success(data, miningPool, size, base, quote);

        vm.warp(maturity);
        setPriceAt(maturity, data.settlementITM, base, quote);

        vm.expectRevert(
            abi.encodeWithSelector(
                IMiningPool.MiningPool__OptionInTheMoney.selector,
                data.settlementITM,
                data.discount * data.spot
            )
        );

        vm.prank(users.underwriter);
        miningPool.settle(shortTokenId, ud(size));
    }

    function test_settle_RevertIf_OptionInTheMoney() public {
        _test_settle_RevertIf_OptionInTheMoney(_data[0], premiaUSDCMiningPool, 1000000e18, premia, usdc);
        _test_settle_RevertIf_OptionInTheMoney(_data[1], wbtcUSDCMiningPool, 100e18, wbtc, usdc);
    }
}
