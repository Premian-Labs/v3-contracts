// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {IUniswapV3Pool} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol";

import {IOwnableInternal} from "@solidstate/contracts/access/ownable/IOwnableInternal.sol";

import {Test} from "forge-std/Test.sol";

import "forge-std/console2.sol";
import "../Addresses.sol";
import {Assertions} from "../Assertions.sol";
import {IFeedRegistry} from "contracts/adapter/IFeedRegistry.sol";
import {IOracleAdapter} from "contracts/adapter/IOracleAdapter.sol";
import {IUniswapV3Adapter} from "contracts/adapter/uniswap/IUniswapV3Adapter.sol";
import {UniswapV3Adapter} from "contracts/adapter/uniswap/UniswapV3Adapter.sol";
import {UniswapV3AdapterProxy} from "contracts/adapter/uniswap/UniswapV3AdapterProxy.sol";

contract UniswapV3AdapterTest is Test, Assertions {
    uint32 constant PERIOD = 600;
    uint256 constant CARDINALITY_PER_MINUTE = 4;
    uint16 constant TARGET_CARDINALITY = uint16((PERIOD * CARDINALITY_PER_MINUTE) / 60);

    IUniswapV3Factory constant UNISWAP_V3_FACTORY = IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    struct Pool {
        address tokenIn;
        address tokenOut;
    }

    Pool[] pools;
    UniswapV3Adapter adapter;

    uint256 mainnetFork;
    uint256 target;
    string rpcUrl;

    function setUp() public {
        rpcUrl = string.concat("https://eth-mainnet.alchemyapi.io/v2/", vm.envString("API_KEY_ALCHEMY"));
        mainnetFork = vm.createFork(rpcUrl, 16597500);
        vm.selectFork(mainnetFork);

        target = 1676016000;

        pools.push(Pool(WETH, WBTC));
        pools.push(Pool(WBTC, WETH));
        pools.push(Pool(WBTC, USDC));
        pools.push(Pool(WBTC, USDT));
        pools.push(Pool(WETH, USDT));
        pools.push(Pool(USDT, WETH));
        pools.push(Pool(WETH, DAI));
        pools.push(Pool(MKR, USDC));
        pools.push(Pool(BOND, WETH));
        pools.push(Pool(USDT, USDC));
        pools.push(Pool(DAI, USDC));
        pools.push(Pool(FXS, FRAX));
        pools.push(Pool(FRAX, FXS));
        pools.push(Pool(FRAX, USDT));
        pools.push(Pool(UNI, USDT));
        pools.push(Pool(LINK, UNI));
        pools.push(Pool(MATIC, WETH));
        pools.push(Pool(MATIC, USDC));
        pools.push(Pool(DAI, USDT));

        _deployAdapter();
    }

    function _deployAdapter() internal {
        address implementation = address(new UniswapV3Adapter(UNISWAP_V3_FACTORY, WETH, 22250, 30000));
        address proxy = address(new UniswapV3AdapterProxy(PERIOD, CARDINALITY_PER_MINUTE, implementation));
        adapter = UniswapV3Adapter(proxy);
    }

    function test_constructor_ShouldSetStateVariables() public {
        assertEq(adapter.getTargetCardinality(), uint256(TARGET_CARDINALITY));
        assertEq(adapter.getPeriod(), PERIOD);
        assertEq(adapter.getCardinalityPerMinute(), CARDINALITY_PER_MINUTE);

        uint24[] memory feeTiers = adapter.getSupportedFeeTiers();
        assertEq(feeTiers.length, 4);
        assertEq(feeTiers[0], 100);
        assertEq(feeTiers[1], 500);
        assertEq(feeTiers[2], 3000);
        assertEq(feeTiers[3], 10000);
    }

    function test_constructor_RevertIf_CardinalityPerMinuteIsZero() public {
        address implementation = address(new UniswapV3Adapter(UNISWAP_V3_FACTORY, WETH, 22250, 30000));

        vm.expectRevert(UniswapV3AdapterProxy.UniswapV3AdapterProxy__CardinalityPerMinuteNotSet.selector);
        new UniswapV3AdapterProxy(PERIOD, 0, implementation);
    }

    function test_constructor_RevertIf_PeriodIsZero() public {
        address implementation = address(new UniswapV3Adapter(UNISWAP_V3_FACTORY, WETH, 22250, 30000));

        vm.expectRevert(UniswapV3AdapterProxy.UniswapV3AdapterProxy__PeriodNotSet.selector);
        new UniswapV3AdapterProxy(0, CARDINALITY_PER_MINUTE, implementation);
    }

    function test_isPairSupported_ReturnTrue_IfPairCachedAndPathExists() public {
        for (uint256 i = 0; i < pools.length; i++) {
            Pool memory p = pools[i];

            adapter.upsertPair(p.tokenIn, p.tokenOut);

            (bool isCached, bool hasPath) = adapter.isPairSupported(p.tokenIn, p.tokenOut);
            assertTrue(isCached);
            assertTrue(hasPath);
        }
    }

    function test_isPairSupported_ReturnFalse_IfPairIsNotSupported() public {
        (bool isCached, ) = adapter.isPairSupported(WETH, DAI);
        assertFalse(isCached);
    }

    function test_isPairSupported_ReturnFalse_IfPairDoesNotExist() public {
        (, bool hasPath) = adapter.isPairSupported(WETH, address(0));
        assertFalse(hasPath);
    }

    function test_upsertPair_RevertIf_PairCannotBeSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector, address(0), WETH)
        );
        adapter.upsertPair(address(0), WETH);

        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector, WBTC, address(0))
        );
        adapter.upsertPair(WBTC, address(0));
    }

    function test_upsertPair_NotRevert_IfCalledMultipleTimes_ForSamePair() public {
        adapter.upsertPair(WETH, WBTC);
        (bool isCached, ) = adapter.isPairSupported(WETH, WBTC);
        assertTrue(isCached);
        adapter.upsertPair(WETH, WBTC);
    }

    function test_getPrice_ReturnQuoteForPair() public {
        // Expected values exported from Defilama
        UD60x18[19] memory expected = [
            ud(70927436248222092), // WETH BTC
            ud(14098916482760458280), // WBTC WETH
            ud(21875331315600487869233), // WBTC USDC
            ud(21861693299762195238145), // WBTC USDT
            ud(1550593857797067130377), // WETH USDT
            ud(644914201724430), // USDT WETH
            ud(1551629452512373291029), // WETH DAI
            ud(718722307016789386580), // MKR USDC
            ud(2715536643539722), // BOND WETH
            ud(1000623831633318250), // USDT USDC
            ud(999955991286274770), // DAI USDC
            ud(11974365585459636918), // FXS FRAX
            ud(83511731194702371), // FRAX FXS
            ud(1000412854982727806), // FRAX USDT
            ud(6442928385508826850), // UNI USDT
            ud(1086000168337553529), // LINK UNI
            ud(831585307611037), // MATIC WETH
            ud(1290255470583175468), // MATIC USDC
            ud(999332576013152396) // DAI USDT
        ];

        for (uint256 i = 0; i < pools.length; i++) {
            Pool memory p = pools[i];
            adapter.upsertPair(p.tokenIn, p.tokenOut);

            UD60x18 price = adapter.getPrice(p.tokenIn, p.tokenOut);

            assertApproxEqAbs(
                price.unwrap(),
                expected[i].unwrap(),
                (expected[i].unwrap() * 2) / 100 // 2% tolerance
            );
        }
    }

    function test_getPrice_RevertIf_PairNotSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOracleAdapter.OracleAdapter__PairNotSupported.selector, WETH, address(0))
        );
        adapter.getPrice(WETH, address(0));
    }

    function test_getPrice_RevertIf_PairNotAdded_AndCardinalityMustBeIncreased() public {
        adapter.setCardinalityPerMinute(200);
        vm.expectRevert(
            abi.encodeWithSelector(IUniswapV3Adapter.UniswapV3Adapter__ObservationCardinalityTooLow.selector, 1, 2000)
        );
        adapter.getPrice(WETH, DAI);
    }

    function test_getPrice_FindPath_IfPairNotAdded() public {
        // must increase cardinality to 40 for pool
        IUniswapV3Pool(0xD8dEC118e1215F02e10DB846DCbBfE27d477aC19).increaseObservationCardinalityNext(
            TARGET_CARDINALITY
        );

        assertGt(adapter.getPrice(WETH, DAI).unwrap(), 0);
    }

    function test_getPrice_SkipUninitializedPools_AndProvideQuote_WhenNoPoolsCached() public {
        address tokenIn = WETH;
        address tokenOut = MKR;

        IUniswapV3Pool(0x886072A44BDd944495eFF38AcE8cE75C1EacDAF6).increaseObservationCardinalityNext(
            TARGET_CARDINALITY
        );

        IUniswapV3Pool(0x3aFdC5e6DfC0B0a507A8e023c9Dce2CAfC310316).increaseObservationCardinalityNext(
            TARGET_CARDINALITY
        );

        IUniswapV3Factory(UNISWAP_V3_FACTORY).createPool(tokenIn, tokenOut, 100);
        assertGt(adapter.getPrice(tokenIn, tokenOut).unwrap(), 0);
    }

    function test_getPrice_SkipUninitializedPools_AndProvideQuote_WhenPoolsAreCached() public {
        address tokenIn = WETH;
        address tokenOut = MKR;

        adapter.upsertPair(tokenIn, tokenOut);
        assertGt(adapter.getPrice(tokenIn, tokenOut).unwrap(), 0);

        IUniswapV3Factory(UNISWAP_V3_FACTORY).createPool(tokenIn, tokenOut, 100);
        assertGt(adapter.getPrice(tokenIn, tokenOut).unwrap(), 0);

        IUniswapV3Pool(0xd9d92C02a8fd1DdB731381f1351DACA19928E0db).initialize(4295128740);

        vm.expectRevert(
            abi.encodeWithSelector(
                IUniswapV3Adapter.UniswapV3Adapter__ObservationCardinalityTooLow.selector,
                1,
                TARGET_CARDINALITY
            )
        );
        adapter.getPrice(tokenIn, tokenOut);

        IUniswapV3Pool(0xd9d92C02a8fd1DdB731381f1351DACA19928E0db).increaseObservationCardinalityNext(
            TARGET_CARDINALITY
        );

        vm.warp(block.timestamp + 600);
        assertGt(adapter.getPrice(tokenIn, tokenOut).unwrap(), 0);
    }

    function test_getPrice_ReturnQuote_UsingCorrectDenomination() public {
        address tokenIn = WETH; // 18 decimals
        address tokenOut = DAI; // 18 decimals

        adapter.upsertPair(tokenIn, tokenOut);

        UD60x18 price = adapter.getPrice(tokenIn, tokenOut);
        UD60x18 invertedQuote = adapter.getPrice(tokenOut, tokenIn);
        assertApproxEqAbs(
            price.unwrap(),
            (ud(1e18) / invertedQuote).unwrap(),
            price.unwrap() / 10000 // 0.01% tolerance
        );

        //

        tokenIn = WETH; // 18 decimals
        tokenOut = USDT; // 8 decimals

        adapter.upsertPair(tokenIn, tokenOut);

        price = adapter.getPrice(tokenIn, tokenOut);
        invertedQuote = adapter.getPrice(tokenOut, tokenIn);

        assertApproxEqAbs(
            price.unwrap(),
            (ud(1e18) / invertedQuote).unwrap(),
            price.unwrap() / 10000 // 0.01% tolerance
        );

        //

        tokenIn = WBTC; // 8 decimals
        tokenOut = USDC; // 6 decimals

        adapter.upsertPair(tokenIn, tokenOut);

        price = adapter.getPrice(tokenIn, tokenOut);
        invertedQuote = adapter.getPrice(tokenOut, tokenIn);

        assertApproxEqAbs(
            price.unwrap(),
            (ud(1e18) / invertedQuote).unwrap(),
            price.unwrap() / 10000 // 0.01% tolerance
        );
    }

    function test_getPriceAt_ReturnQuoteForPairFromTarget() public {
        // Expected values exported from Defilama
        UD60x18[19] memory expected = [
            ud(70759868720940824), // WETH BTC
            ud(14132304342504493633), // WBTC WETH
            ud(21894211576846308162203), // WBTC USDC
            ud(21916083916083916847128), // WBTC USDT
            ud(1550779220779220850090), // WETH USDT
            ud(644837115819446), // USDT WETH
            ud(1550779220779220850090), // WETH DAI
            ud(719770459081836406767), // MKR USDC
            ud(2731377993081368), // BOND WETH
            ud(999001996007983895), // USDT USDC
            ud(999001996007983895), // DAI USDC
            ud(12280075126207080416), // FXS FRAX
            ud(81432726569065195), // FRAX FXS
            ud(1001435428636556102), // FRAX USDT
            ud(6453546453546453954), // UNI USDT
            ud(1080495356037151744), // LINK UNI
            ud(811683082849652), // MATIC WETH
            ud(1257485029940119681), // MATIC USDC
            ud(1000000000000000000) // DAI USDT
        ];

        for (uint256 i = 0; i < pools.length; i++) {
            Pool memory p = pools[i];
            adapter.upsertPair(p.tokenIn, p.tokenOut);

            UD60x18 price = adapter.getPriceAt(p.tokenIn, p.tokenOut, target);

            assertApproxEqAbs(
                price.unwrap(),
                expected[i].unwrap(),
                (expected[i].unwrap() * 2) / 100 // 2% tolerance
            );
        }
    }

    function test_getPriceAt_RevertIf_OldestObservationLessThanTwapPeriod() public {
        mainnetFork = vm.createFork(rpcUrl, 16597040);
        vm.selectFork(mainnetFork);
        _deployAdapter();

        adapter.upsertPair(UNI, AAVE);

        vm.expectRevert(
            abi.encodeWithSelector(IUniswapV3Adapter.UniswapV3Adapter__InsufficientObservationPeriod.selector, 480, 600)
        );
        adapter.getPriceAt(UNI, AAVE, target);
    }

    function test_poolsForPair_ReturnPoolsForPair() public {
        address[] memory _pools = adapter.poolsForPair(WETH, DAI);
        assertEq(_pools.length, 0);

        adapter.upsertPair(WETH, DAI);
        _pools = adapter.poolsForPair(WETH, DAI);
        assertEq(_pools.length, 4);
        assertEq(_pools[0], 0xD8dEC118e1215F02e10DB846DCbBfE27d477aC19);
        assertEq(_pools[1], 0x60594a405d53811d3BC4766596EFD80fd545A270);
        assertEq(_pools[2], 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
        assertEq(_pools[3], 0xa80964C5bBd1A0E95777094420555fead1A26c1e);
    }

    function test_getFactory_ReturnExpectedValue() public {
        assertEq(address(adapter.getFactory()), address(UNISWAP_V3_FACTORY));
    }

    function test_getPeriod_ReturnExpectedValue() public {
        assertEq(adapter.getPeriod(), 600);
    }

    function test_getCardinalityPerMinute_ReturnExpectedValue() public {
        assertEq(adapter.getCardinalityPerMinute(), 4);
    }

    function test_getGasPerCardinality_ReturnExpectedValue() public {
        assertEq(adapter.getGasPerCardinality(), 22250);
    }

    function test_getGasToSupportPool_ReturnExpectedValue() public {
        assertEq(adapter.getGasToSupportPool(), 30000);
    }

    function test_getSupportedFeeTiers_ReturnExpectedValue() public {
        uint24[] memory feeTiers = adapter.getSupportedFeeTiers();
        assertEq(feeTiers.length, 4);
        assertEq(feeTiers[0], 100);
        assertEq(feeTiers[1], 500);
        assertEq(feeTiers[2], 3000);
        assertEq(feeTiers[3], 10000);
    }

    function test_setPeriod_SetNewPeriod() public {
        adapter.setPeriod(800);
        assertEq(adapter.getPeriod(), 800);
    }

    function test_setPeriod_RevertIf_NotCalledByOwner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(vm.addr(111));
        adapter.setPeriod(800);
    }

    function test_setPeriod_RevertIf_NewValueIsZero() public {
        vm.expectRevert(IUniswapV3Adapter.UniswapV3Adapter__PeriodNotSet.selector);
        adapter.setPeriod(0);
    }

    function test_setPeriod_SetCardinalityPerMinute() public {
        adapter.setCardinalityPerMinute(8);
        assertEq(adapter.getCardinalityPerMinute(), 8);
    }

    function test_setCardinalityPerMinute_RevertIf_NotCalledByOwner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(vm.addr(111));
        adapter.setCardinalityPerMinute(8);
    }

    function test_setCardinalityPerMinute_RevertIf_NewValueIsZero() public {
        vm.expectRevert(IUniswapV3Adapter.UniswapV3Adapter__CardinalityPerMinuteNotSet.selector);
        adapter.setCardinalityPerMinute(0);
    }

    function test_insertFeeTier_RevertIf_NotCalledByOwner() public {
        vm.expectRevert(IOwnableInternal.Ownable__NotOwner.selector);
        vm.prank(vm.addr(111));
        adapter.insertFeeTier(200);
    }

    function test_insertFeeTier_RevertIf_FeeTierInvalid() public {
        vm.expectRevert(abi.encodeWithSelector(IUniswapV3Adapter.UniswapV3Adapter__InvalidFeeTier.selector, 200));
        adapter.insertFeeTier(200);
    }

    function test_insertFeeTier_RevertIf_FeeTierAlreadyExists() public {
        vm.expectRevert(abi.encodeWithSelector(IUniswapV3Adapter.UniswapV3Adapter__FeeTierExists.selector, 10000));
        adapter.insertFeeTier(10000);
    }

    function test_describePricingPath_DescribePricingPath() public {
        (IOracleAdapter.AdapterType adapterType, address[][] memory path, uint8[] memory decimals) = adapter
            .describePricingPath(address(1));

        assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.UniswapV3));
        assertEq(path.length, 0);
        assertEq(decimals.length, 0);

        //

        (adapterType, path, decimals) = adapter.describePricingPath(WETH);

        assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.UniswapV3));
        assertEq(path[0].length, 1);
        assertEq(path[0][0], 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE);
        assertEq(decimals.length, 1);
        assertEq(decimals[0], 18);

        //

        (adapterType, path, decimals) = adapter.describePricingPath(DAI);

        assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.UniswapV3));
        assertEq(path[0].length, 4);
        assertEq(path[0][0], 0xD8dEC118e1215F02e10DB846DCbBfE27d477aC19);
        assertEq(path[0][1], 0x60594a405d53811d3BC4766596EFD80fd545A270);
        assertEq(path[0][2], 0xC2e9F25Be6257c210d7Adf0D4Cd6E3E881ba25f8);
        assertEq(path[0][3], 0xa80964C5bBd1A0E95777094420555fead1A26c1e);
        assertEq(decimals.length, 2);
        assertEq(decimals[0], 18);
        assertEq(decimals[1], 18);

        //

        (adapterType, path, decimals) = adapter.describePricingPath(USDC);

        assertEq(uint256(adapterType), uint256(IOracleAdapter.AdapterType.UniswapV3));
        assertEq(path[0].length, 4);
        assertEq(path[0][0], 0xE0554a476A092703abdB3Ef35c80e0D76d32939F);
        assertEq(path[0][1], 0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640);
        assertEq(path[0][2], 0x8ad599c3A0ff1De082011EFDDc58f1908eb6e6D8);
        assertEq(path[0][3], 0x7BeA39867e4169DBe237d55C8242a8f2fcDcc387);
        assertEq(decimals.length, 2);
        assertEq(decimals[0], 6);
        assertEq(decimals[1], 18);
    }
}
