// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.19;

import {UD60x18, ud} from "@prb/math/UD60x18.sol";
import {SD59x18, sd} from "@prb/math/SD59x18.sol";

import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";

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
    IUniswapV3Factory constant UNISWAP_V3_FACTORY =
        IUniswapV3Factory(0x1F98431c8aD98523631AE4a59f267346ea31F984);

    struct Pool {
        address tokenIn;
        address tokenOut;
    }

    Pool[] pools;
    UniswapV3Adapter adapter;

    uint256 mainnetFork;
    uint256 target;

    function setUp() public {
        string memory ETH_RPC_URL = string.concat(
            "https://eth-mainnet.alchemyapi.io/v2/",
            vm.envString("API_KEY_ALCHEMY")
        );
        mainnetFork = vm.createFork(ETH_RPC_URL, 16597500);
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

        address implementation = address(
            new UniswapV3Adapter(UNISWAP_V3_FACTORY, WETH, 22250, 30000)
        );
        address proxy = address(
            new UniswapV3AdapterProxy(
                PERIOD,
                CARDINALITY_PER_MINUTE,
                implementation
            )
        );
        adapter = UniswapV3Adapter(proxy);
    }

    function test_constructor_RevertIf_CardinalityPerMinuteIsZero() public {
        address implementation = address(
            new UniswapV3Adapter(UNISWAP_V3_FACTORY, WETH, 22250, 30000)
        );

        vm.expectRevert(
            UniswapV3AdapterProxy
                .UniswapV3AdapterProxy__CardinalityPerMinuteNotSet
                .selector
        );
        new UniswapV3AdapterProxy(PERIOD, 0, implementation);
    }
}
