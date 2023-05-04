import { diamondCut } from '../scripts/utils/diamond';
import {
  PoolBase__factory,
  PoolCore__factory,
  PoolFactory,
  PoolFactory__factory,
  PoolFactoryProxy__factory,
  PoolCoreMock__factory,
  PoolDepositWithdraw__factory,
  Premia,
  Premia__factory,
  PoolTrade__factory,
  ERC20Router__factory,
  ERC20Router,
  InitFeeCalculator__factory,
  ProxyUpgradeableOwnable__factory,
  ERC20Mock__factory,
  VxPremia__factory,
  VxPremiaProxy__factory,
  ExchangeHelper__factory,
  Referral__factory,
} from '../typechain';
import { Interface } from '@ethersproject/abi';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumber, constants } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import { tokens } from '../utils/addresses';

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
    poolFactory: string,
    router: string,
    vxPremia: string,
    wrappedNativeToken: string,
    feeReceiver: string,
    referralAddress: string,
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
      wrappedNativeToken,
      feeReceiver,
      referralAddress,
      vxPremia,
    );
    await poolCoreImpl.deployed();

    if (log) console.log(`PoolCore : ${poolCoreImpl.address}`);

    result.push({
      name: 'PoolCore',
      address: poolCoreImpl.address,
      interface: poolCoreImpl.interface,
    });

    // PoolDepositWithdraw

    const poolDepositWithdrawFactory = new PoolDepositWithdraw__factory(
      deployer,
    );
    const poolDepositWithdrawImpl = await poolDepositWithdrawFactory.deploy(
      poolFactory,
      router,
      wrappedNativeToken,
      feeReceiver,
      referralAddress,
      vxPremia,
    );
    await poolDepositWithdrawImpl.deployed();

    if (log) {
      console.log(`PoolDepositWithdraw : ${poolDepositWithdrawImpl.address}`);
    }

    result.push({
      name: 'PoolDepositWithdraw',
      address: poolDepositWithdrawImpl.address,
      interface: poolDepositWithdrawImpl.interface,
    });

    // PoolTrade

    const poolTradeFactory = new PoolTrade__factory(deployer);
    const poolTradeImpl = await poolTradeFactory.deploy(
      poolFactory,
      router,
      wrappedNativeToken,
      feeReceiver,
      referralAddress,
      vxPremia,
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
        wrappedNativeToken,
        feeReceiver,
        referralAddress,
        vxPremia,
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
    vxPremiaAddress?: string,
  ) {
    // Diamond and facets deployment
    const premiaDiamond = await new Premia__factory(deployer).deploy();
    await premiaDiamond.deployed();

    if (log) console.log(`Premia Diamond : ${premiaDiamond.address}`);

    //////////////////////////////////////////////

    /////////////////
    // PoolFactory //
    /////////////////

    const initFeeImpl = await new InitFeeCalculator__factory(deployer).deploy(
      wrappedNativeToken,
      chainlinkAdapter,
    );

    await initFeeImpl.deployed();

    if (log) console.log(`InitFeeCalculator impl: ${initFeeImpl.address}`);

    const initFeeProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(initFeeImpl.address);

    await initFeeProxy.deployed();

    if (log) console.log(`InitFeeCalculator proxy: ${initFeeProxy.address}`);

    const poolFactoryImpl = await new PoolFactory__factory(deployer).deploy(
      premiaDiamond.address,
      chainlinkAdapter,
      initFeeProxy.address,
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

    // VxPremia
    if (!vxPremiaAddress) {
      const premia = await new ERC20Mock__factory(deployer).deploy(
        'PREMIA',
        18,
      );

      if (log) console.log(`Premia : ${exchangeHelper.address}`);

      const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
        constants.AddressZero,
        constants.AddressZero,
        premia.address,
        tokens.USDC.address,
        exchangeHelper.address,
      );

      await vxPremiaImpl.deployed();

      if (log) console.log(`VxPremia : ${vxPremiaImpl.address}`);

      const vxPremiaProxy = await new VxPremiaProxy__factory(deployer).deploy(
        vxPremiaImpl.address,
      );

      await vxPremiaProxy.deployed();

      if (log) console.log(`VxPremiaProxy : ${vxPremiaProxy.address}`);

      vxPremiaAddress = vxPremiaProxy.address;
    }

    const referralImpl = await new Referral__factory(deployer).deploy();

    await referralImpl.deployed();

    if (log) console.log(`Referral : ${referralImpl.address}`);

    const referralProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(referralImpl.address);

    await referralProxy.deployed();

    if (log) console.log(`ReferralProxy : ${referralProxy.address}`);

    const deployedFacets = await PoolUtil.deployPoolImplementations(
      deployer,
      poolFactory.address,
      router.address,
      vxPremiaAddress,
      wrappedNativeToken,
      feeReceiver,
      referralProxy.address,
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
