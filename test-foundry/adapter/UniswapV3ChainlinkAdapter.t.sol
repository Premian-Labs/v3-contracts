// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

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
import {ChainlinkAdapter} from "contracts/adapter/chainlink/ChainlinkAdapter.sol";
import {IUniswapV3ChainlinkAdapter} from "contracts/adapter/composite/IUniswapV3ChainlinkAdapter.sol";
import {UniswapV3ChainlinkAdapter} from "contracts/adapter/composite/UniswapV3ChainlinkAdapter.sol";
import {UniswapV3Adapter} from "contracts/adapter/uniswap/UniswapV3Adapter.sol";
import {UniswapV3AdapterProxy} from "contracts/adapter/uniswap/UniswapV3AdapterProxy.sol";
import {ProxyUpgradeableOwnable} from "contracts/proxy/ProxyUpgradeableOwnable.sol";

contract UniswapV3ChainlinkAdapterTest is Test, Assertions {
    uint32 constant PERIOD = 600;
    uint256 constant CARDINALITY_PER_MINUTE = 4;
    IUniswapV3Factory constant UNISWAP_V3_FACTORY =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    struct Pool {
        address tokenIn;
        address tokenOut;
    }

    Pool[] pools;
    UniswapV3ChainlinkAdapter adapter;

    uint256 mainnetFork;
    uint256 target;
    string rpcUrl;

    function setUp() public {
        rpcUrl = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );
        mainnetFork = vm.createFork(rpcUrl, 16597500);
        vm.selectFork(mainnetFork);

        target = 1676016000;

        pools.push(Pool(WBTC, USDC));
        pools.push(Pool(WBTC, USDT));
        pools.push(Pool(WBTC, DAI));
        pools.push(Pool(MKR, USDC));
        pools.push(Pool(MKR, ENS));
        pools.push(Pool(USDT, DAI));
        pools.push(Pool(USDT, USDC));
        pools.push(Pool(DAI, USDC));
        pools.push(Pool(DAI, LINK));
        pools.push(Pool(UNI, USDT));
        pools.push(Pool(LINK, UNI));
        pools.push(Pool(MATIC, USDC));
        pools.push(Pool(BIT, USDC));
        pools.push(Pool(GNO, LINK));
        pools.push(Pool(LOOKS, USDC));
        pools.push(Pool(LOOKS, WBTC));

        // Deploy ChainlinkAdapter
        address chainlinkAdapterImplementation = address(
            new ChainlinkAdapter(WETH, WBTC)
        );
        address chainlinkAdapterProxy = address(
            new ProxyUpgradeableOwnable(chainlinkAdapterImplementation)
        );

        ChainlinkAdapter(chainlinkAdapterProxy).batchRegisterFeedMappings(
            feeds()
        );

        // Deploy UniswapV3Adapter
        address uniswapV3AdapterImplementation = address(
            new UniswapV3Adapter(UNISWAP_V3_FACTORY, WETH, 22250, 30000)
        );

        address uniswapV3AdapterProxy = address(
            new UniswapV3AdapterProxy(
                PERIOD,
                CARDINALITY_PER_MINUTE,
                uniswapV3AdapterImplementation
            )
        );

        // Deploy UniswapV3ChainlinkAdapter
        address uniswapV3ChainlinkAdapterImplementation = address(
            new UniswapV3ChainlinkAdapter(
                IOracleAdapter(chainlinkAdapterProxy),
                IOracleAdapter(uniswapV3AdapterProxy),
                WETH
            )
        );

        address uniswapV3ChainlinkAdapterProxy = address(
            new ProxyUpgradeableOwnable(uniswapV3ChainlinkAdapterImplementation)
        );

        adapter = UniswapV3ChainlinkAdapter(uniswapV3ChainlinkAdapterProxy);
    }

    function test_isPairSupported_ReturnFalse_IfPairNotSupported() public {
        (bool isCached, ) = adapter.isPairSupported(address(1), DAI);
        assertFalse(isCached);

        (isCached, ) = adapter.isPairSupported(DAI, address(1));
        assertFalse(isCached);
    }

    function test_isPairSupported_ReturnFalse_IfPathForPairDoesNotExist()
        public
    {
        (, bool hasPath) = adapter.isPairSupported(address(1), DAI);
        assertFalse(hasPath);

        (, hasPath) = adapter.isPairSupported(DAI, address(1));
        assertFalse(hasPath);
    }

    function test_isPairSupported_RevertIf_TokenIsWrappedNativeToken() public {
        vm.expectRevert(
            IUniswapV3ChainlinkAdapter
                .UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative
                .selector
        );
        adapter.isPairSupported(WETH, DAI);

        vm.expectRevert(
            IUniswapV3ChainlinkAdapter
                .UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative
                .selector
        );
        adapter.isPairSupported(DAI, WETH);
    }

    function test_upsertPair_UpsertPair_IfNotAlreadyCachedInUpstreamAdapters()
        public
    {
        address tokenA = EUL;
        address tokenB = DAI;

        (bool isCached, ) = adapter.isPairSupported(tokenA, tokenB);
        assertFalse(isCached);

        adapter.upsertPair(tokenA, tokenB);

        (isCached, ) = adapter.isPairSupported(tokenA, tokenB);
        assertTrue(isCached);
    }

    function test_upsertPair_RevertIf_TokenIsWrappedNativeToken() public {
        vm.expectRevert(
            IUniswapV3ChainlinkAdapter
                .UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative
                .selector
        );
        adapter.upsertPair(WETH, DAI);

        vm.expectRevert(
            IUniswapV3ChainlinkAdapter
                .UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative
                .selector
        );
        adapter.upsertPair(DAI, WETH);
    }

    function test_upsertPair_RevertIf_PairCannotBeSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                address(1),
                WETH
            )
        );
        adapter.upsertPair(address(1), DAI);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                WETH,
                address(1)
            )
        );
        adapter.upsertPair(DAI, address(1));
    }

    function test_quote_RevertIf_TokenIsWrappedNativeToken() public {
        vm.expectRevert(
            IUniswapV3ChainlinkAdapter
                .UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative
                .selector
        );
        adapter.quote(WETH, DAI);

        vm.expectRevert(
            IUniswapV3ChainlinkAdapter
                .UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative
                .selector
        );
        adapter.quote(DAI, WETH);
    }

    function test_quote_RevertIf_PairCannotBeSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                address(1),
                WETH
            )
        );
        adapter.quote(address(1), DAI);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                WETH,
                address(1)
            )
        );
        adapter.quote(DAI, address(1));
    }

    function test_quoteFrom_RevertIf_TokenIsWrappedNativeToken() public {
        vm.expectRevert(
            IUniswapV3ChainlinkAdapter
                .UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative
                .selector
        );
        adapter.quoteFrom(WETH, DAI, target);

        vm.expectRevert(
            IUniswapV3ChainlinkAdapter
                .UniswapV3ChainlinkAdapter__TokenCannotBeWrappedNative
                .selector
        );
        adapter.quoteFrom(DAI, WETH, target);
    }

    function test_quoteFrom_RevertIf_PairCannotBeSupported() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                address(1),
                WETH
            )
        );
        adapter.quoteFrom(address(1), DAI, target);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__PairCannotBeSupported.selector,
                WETH,
                address(1)
            )
        );
        adapter.quoteFrom(DAI, address(1), target);
    }

    function test_quoteFrom_RevertIf_TargetIsZero() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IOracleAdapter.OracleAdapter__InvalidTarget.selector,
                0,
                block.timestamp
            )
        );
        adapter.quoteFrom(EUL, DAI, 0);
    }
}
