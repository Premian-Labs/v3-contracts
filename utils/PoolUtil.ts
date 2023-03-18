import {
  PoolBase__factory,
  PoolCore__factory,
  PoolFactory,
  PoolFactory__factory,
  PoolFactoryProxy__factory,
  PoolCoreMock__factory,
  Premia,
  Premia__factory,
  ExchangeHelper__factory,
  PoolTrade__factory,
  ERC20Router__factory,
  ERC20Router,
} from '../typechain';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { diamondCut } from '../scripts/utils/diamond';
import { BigNumber } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import { Interface } from '@ethersproject/abi';
interface PoolUtilArgs {
  premiaDiamond: Premia;
  poolFactory: PoolFactory;
  router: ERC20Router;
}

interface DeployedFacets {
  name: string;
  address: string;
  interface: Interface;
}

export class PoolUtil {
  premiaDiamond: Premia;
  poolFactory: PoolFactory;
  router: ERC20Router;

  constructor(args: PoolUtilArgs) {
    this.premiaDiamond = args.premiaDiamond;
    this.poolFactory = args.poolFactory;
    this.router = args.router;
  }

  static async deployPoolImplementations(
    deployer: SignerWithAddress,
    premiaDiamond: string,
    poolFactory: string,
    router: string,
    exchangeHelper: string,
    wrappedNativeToken: string,
    chainlinkAdapter: string,
    feeReceiver: string,
    discountPerPool: BigNumber = parseEther('0.1'), // 10%
    log = true,
    isDevMode = false,
  ) {
    const result: DeployedFacets[] = [];

    // PoolBase
    const poolBaseFactory = new PoolBase__factory(deployer);
    const poolBaseImpl = await poolBaseFactory.deploy();
    await poolBaseImpl.deployed();

    if (log) console.log(`PoolBase : ${poolBaseImpl.address}`);

    result.push({
      name: 'PoolBase',
      address: poolBaseImpl.address,
      interface: poolBaseImpl.interface,
    });

    // PoolCore

    const poolCoreFactory = new PoolCore__factory(deployer);
    const poolCoreImpl = await poolCoreFactory.deploy(
      poolFactory,
      router,
      exchangeHelper,
      wrappedNativeToken,
      feeReceiver,
    );
    await poolCoreImpl.deployed();

    if (log) console.log(`PoolCore : ${poolCoreImpl.address}`);

    result.push({
      name: 'PoolCore',
      address: poolCoreImpl.address,
      interface: poolCoreImpl.interface,
    });

    // PoolTrade

    const poolTradeFactory = new PoolTrade__factory(deployer);
    const poolTradeImpl = await poolTradeFactory.deploy(
      poolFactory,
      router,
      exchangeHelper,
      wrappedNativeToken,
      feeReceiver,
    );
    await poolTradeImpl.deployed();

    if (log) {
      console.log(`PoolTrade : ${poolTradeImpl.address}`);
    }

    result.push({
      name: 'PoolTrade',
      address: poolTradeImpl.address,
      interface: poolTradeImpl.interface,
    });

    // PoolCoreMock

    if (isDevMode) {
      const poolCoreMockFactory = new PoolCoreMock__factory(deployer);
      const poolCoreMockImpl = await poolCoreMockFactory.deploy(
        poolFactory,
        router,
        exchangeHelper,
        wrappedNativeToken,
        feeReceiver,
      );
      await poolCoreMockImpl.deployed();

      if (log) console.log(`PoolCoreMock : ${poolCoreMockImpl.address}`);

      result.push({
        name: 'PoolCoreMock',
        address: poolCoreMockImpl.address,
        interface: poolCoreMockImpl.interface,
      });
    }

    return result;
  }

  static async deploy(
    deployer: SignerWithAddress,
    wrappedNativeToken: string,
    chainlinkAdapter: string,
    feeReceiver: string,
    discountPerPool: BigNumber = parseEther('0.1'), // 10%
    log = true,
    isDevMode = false,
  ) {
    // Diamond and facets deployment
    const premiaDiamond = await new Premia__factory(deployer).deploy();
    await premiaDiamond.deployed();

    if (log) console.log(`Premia Diamond : ${premiaDiamond.address}`);

    //////////////////////////////////////////////

    /////////////////
    // PoolFactory //
    /////////////////

    const poolFactoryImpl = await new PoolFactory__factory(deployer).deploy(
      premiaDiamond.address,
      chainlinkAdapter,
      wrappedNativeToken,
    );

    await poolFactoryImpl.deployed();

    if (log) console.log(`PoolFactory : ${poolFactoryImpl.address}`);

    const poolFactoryProxy = await new PoolFactoryProxy__factory(
      deployer,
    ).deploy(poolFactoryImpl.address, discountPerPool, feeReceiver);
    await poolFactoryProxy.deployed();

    if (log) console.log(`PoolFactoryProxy : ${poolFactoryProxy.address}`);

    const poolFactory = PoolFactory__factory.connect(
      poolFactoryProxy.address,
      deployer,
    );

    //////////////////////////////////////////////

    //////////
    // Pool //
    //////////

    // ERC20Router
    const router = await new ERC20Router__factory(deployer).deploy(
      poolFactory.address,
    );
    await router.deployed();

    if (log) console.log(`ERC20Router : ${router.address}`);

    // ExchangeHelper
    const exchangeHelper = await new ExchangeHelper__factory(deployer).deploy();
    await exchangeHelper.deployed();

    if (log) console.log(`ExchangeHelper : ${exchangeHelper.address}`);

    const deployedFacets = await PoolUtil.deployPoolImplementations(
      deployer,
      premiaDiamond.address,
      poolFactory.address,
      router.address,
      exchangeHelper.address,
      wrappedNativeToken,
      chainlinkAdapter,
      feeReceiver,
      discountPerPool,
      log,
      isDevMode,
    );

    let registeredSelectors = [
      premiaDiamond.interface.getSighash('supportsInterface(bytes4)'),
    ];

    for (const el of deployedFacets) {
      registeredSelectors = registeredSelectors.concat(
        await diamondCut(
          premiaDiamond,
          el.address,
          el.interface,
          registeredSelectors,
        ),
      );
    }

    return new PoolUtil({ premiaDiamond, poolFactory, router });
  }
}
