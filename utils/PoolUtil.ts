import { diamondCut } from '../scripts/utils/diamond';
import {
  ERC20Mock__factory,
  ERC20Router,
  ERC20Router__factory,
  ExchangeHelper__factory,
  IReferral,
  IReferral__factory,
  Placeholder__factory,
  PoolBase__factory,
  PoolCore__factory,
  PoolCoreMock__factory,
  PoolDepositWithdraw__factory,
  PoolFactory,
  PoolFactory__factory,
  PoolFactoryDeployer__factory,
  PoolFactoryProxy__factory,
  PoolTrade__factory,
  Premia,
  Premia__factory,
  ProxyUpgradeableOwnable__factory,
  Referral__factory,
  ReferralProxy__factory,
  UserSettings__factory,
  VaultRegistry__factory,
  VxPremia__factory,
  VxPremiaProxy__factory,
} from '../typechain';
import { Interface } from '@ethersproject/abi';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/dist/src/signer-with-address';
import { BigNumber, constants } from 'ethers';
import { parseEther } from 'ethers/lib/utils';
import { tokens } from './addresses';

interface PoolUtilArgs {
  premiaDiamond: Premia;
  poolFactory: PoolFactory;
  router: ERC20Router;
  referral: IReferral;
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
  referral: IReferral;

  constructor(args: PoolUtilArgs) {
    this.premiaDiamond = args.premiaDiamond;
    this.poolFactory = args.poolFactory;
    this.router = args.router;
    this.referral = args.referral;
  }

  static async deployPoolImplementations(
    deployer: SignerWithAddress,
    poolFactory: string,
    router: string,
    userSettings: string,
    vxPremia: string,
    wrappedNativeToken: string,
    feeReceiver: string,
    referralAddress: string,
    vaultRegistry: string,
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
      userSettings,
      vaultRegistry,
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
      userSettings,
      vaultRegistry,
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
      userSettings,
      vaultRegistry,
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
        userSettings,
        vaultRegistry,
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
    vaultRegistry?: string,
  ) {
    // Diamond and facets deployment
    const premiaDiamond = await new Premia__factory(deployer).deploy();
    await premiaDiamond.deployed();

    if (log) console.log(`Premia Diamond : ${premiaDiamond.address}`);

    //////////////////////////////////////////////

    /////////////////
    // PoolFactory //
    /////////////////

    const placeholder = await new Placeholder__factory(deployer).deploy();
    await placeholder.deployed();

    if (log) console.log(`Placeholder : ${placeholder.address}`);

    const poolFactoryProxy = await new PoolFactoryProxy__factory(
      deployer,
    ).deploy(placeholder.address, discountPerPool, feeReceiver);
    await poolFactoryProxy.deployed();

    if (log) console.log(`PoolFactoryProxy : ${poolFactoryProxy.address}`);

    const poolFactoryDeployer = await new PoolFactoryDeployer__factory(
      deployer,
    ).deploy(premiaDiamond.address, poolFactoryProxy.address);
    await poolFactoryDeployer.deployed();

    if (log)
      console.log(`PoolFactoryDeployer : ${poolFactoryDeployer.address}`);

    const poolFactoryImpl = await new PoolFactory__factory(deployer).deploy(
      premiaDiamond.address,
      chainlinkAdapter,
      wrappedNativeToken,
      poolFactoryDeployer.address,
    );

    await poolFactoryImpl.deployed();

    if (log) console.log(`PoolFactory : ${poolFactoryImpl.address}`);

    await (
      await poolFactoryProxy.setImplementation(poolFactoryImpl.address)
    ).wait();

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

    // UserSettings
    const userSettingsImpl = await new UserSettings__factory(deployer).deploy();
    await userSettingsImpl.deployed();

    if (log) console.log(`UserSettings : ${userSettingsImpl.address}`);

    const userSettingsProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(userSettingsImpl.address);

    await userSettingsProxy.deployed();

    if (log) console.log(`UserSettingsProxy : ${userSettingsProxy.address}`);

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

    // Vault Registry
    if (!vaultRegistry) {
      const vaultRegistryImpl = await new VaultRegistry__factory(
        deployer,
      ).deploy();

      await vaultRegistryImpl.deployed();

      if (log) console.log(`VaultRegistry : ${vaultRegistryImpl.address}`);

      const vaultRegistryProxy = await new ProxyUpgradeableOwnable__factory(
        deployer,
      ).deploy(vaultRegistryImpl.address);

      await vaultRegistryProxy.deployed();

      if (log)
        console.log(`VaultRegistryProxy : ${vaultRegistryProxy.address}`);

      vaultRegistry = vaultRegistryProxy.address;
    }

    const referralImpl = await new Referral__factory(deployer).deploy(
      poolFactory.address,
    );
    await referralImpl.deployed();
    if (log) console.log(`Referral : ${referralImpl.address}`);

    const referralProxy = await new ReferralProxy__factory(deployer).deploy(
      referralImpl.address,
    );

    await referralProxy.deployed();
    if (log) console.log(`ReferralProxy : ${referralProxy.address}`);

    const referral = IReferral__factory.connect(
      referralProxy.address,
      deployer,
    );

    const deployedFacets = await PoolUtil.deployPoolImplementations(
      deployer,
      poolFactory.address,
      router.address,
      userSettingsProxy.address,
      vxPremiaAddress,
      wrappedNativeToken,
      feeReceiver,
      referral.address,
      vaultRegistry,
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

    return new PoolUtil({ premiaDiamond, poolFactory, router, referral });
  }
}
