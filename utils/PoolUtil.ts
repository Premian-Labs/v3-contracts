import { diamondCut } from '../scripts/utils/diamond';
import {
  ERC20Router,
  ERC20Router__factory,
  ExchangeHelper__factory,
  IReferral,
  IReferral__factory,
  Placeholder__factory,
  PoolBase__factory,
  PoolCore__factory,
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
import { updateDeploymentMetadata } from './deployment/deployment';
import { ContractKey, ContractType } from './deployment/types';

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
    verifyContracts: boolean,
  ) {
    const result: DeployedFacets[] = [];

    // PoolBase
    const poolBaseFactory = new PoolBase__factory(deployer);
    const poolBaseImpl = await poolBaseFactory.deploy();
    await updateDeploymentMetadata(
      deployer,
      ContractKey.PoolBase,
      ContractType.DiamondFacet,
      poolBaseImpl,
      [],
      { logTxUrl: true, verification: { enableVerification: verifyContracts } },
    );

    result.push({
      name: ContractKey.PoolBase,
      address: poolBaseImpl.address,
      interface: poolBaseImpl.interface,
    });

    // PoolCore
    const poolCoreFactory = new PoolCore__factory(deployer);

    const poolCoreImplArgs = [
      poolFactory,
      router,
      wrappedNativeToken,
      feeReceiver,
      referralAddress,
      userSettings,
      vaultRegistry,
      vxPremia,
    ];
    const poolCoreImpl = await poolCoreFactory.deploy(
      poolCoreImplArgs[0],
      poolCoreImplArgs[1],
      poolCoreImplArgs[2],
      poolCoreImplArgs[3],
      poolCoreImplArgs[4],
      poolCoreImplArgs[5],
      poolCoreImplArgs[6],
      poolCoreImplArgs[7],
    );
    await updateDeploymentMetadata(
      deployer,
      ContractKey.PoolCore,
      ContractType.DiamondFacet,
      poolCoreImpl,
      poolCoreImplArgs,
      { logTxUrl: true, verification: { enableVerification: verifyContracts } },
    );

    result.push({
      name: ContractKey.PoolCore,
      address: poolCoreImpl.address,
      interface: poolCoreImpl.interface,
    });

    // PoolDepositWithdraw
    const poolDepositWithdrawFactory = new PoolDepositWithdraw__factory(
      deployer,
    );
    const poolDepositWithdrawImplArgs = [
      poolFactory,
      router,
      wrappedNativeToken,
      feeReceiver,
      referralAddress,
      userSettings,
      vaultRegistry,
      vxPremia,
    ];
    const poolDepositWithdrawImpl = await poolDepositWithdrawFactory.deploy(
      poolDepositWithdrawImplArgs[0],
      poolDepositWithdrawImplArgs[1],
      poolDepositWithdrawImplArgs[2],
      poolDepositWithdrawImplArgs[3],
      poolDepositWithdrawImplArgs[4],
      poolDepositWithdrawImplArgs[5],
      poolDepositWithdrawImplArgs[6],
      poolDepositWithdrawImplArgs[7],
    );
    await updateDeploymentMetadata(
      deployer,
      ContractKey.PoolDepositWithdraw,
      ContractType.DiamondFacet,
      poolDepositWithdrawImpl,
      poolDepositWithdrawImplArgs,
      { logTxUrl: true, verification: { enableVerification: verifyContracts } },
    );

    result.push({
      name: ContractKey.PoolDepositWithdraw,
      address: poolDepositWithdrawImpl.address,
      interface: poolDepositWithdrawImpl.interface,
    });

    // PoolTrade
    const poolTradeFactory = new PoolTrade__factory(deployer);

    const poolTradeImplArgs = [
      poolFactory,
      router,
      wrappedNativeToken,
      feeReceiver,
      referralAddress,
      userSettings,
      vaultRegistry,
      vxPremia,
    ];
    const poolTradeImpl = await poolTradeFactory.deploy(
      poolTradeImplArgs[0],
      poolTradeImplArgs[1],
      poolTradeImplArgs[2],
      poolTradeImplArgs[3],
      poolTradeImplArgs[4],
      poolTradeImplArgs[5],
      poolTradeImplArgs[6],
      poolTradeImplArgs[7],
    );
    await updateDeploymentMetadata(
      deployer,
      ContractKey.PoolTrade,
      ContractType.DiamondFacet,
      poolTradeImpl,
      poolTradeImplArgs,
      { logTxUrl: true, verification: { enableVerification: verifyContracts } },
    );

    result.push({
      name: ContractKey.PoolTrade,
      address: poolTradeImpl.address,
      interface: poolTradeImpl.interface,
    });

    return result;
  }

  static async deploy(
    deployer: SignerWithAddress,
    wrappedNativeToken: string,
    chainlinkAdapter: string,
    feeReceiver: string,
    insuranceFund: string,
    discountPerPool: BigNumber = parseEther('0.1'), // 10%
    log = true,
    vxPremiaAddress?: string,
    premiaAddress?: string,
    usdcAddress?: string,
    exchangeHelperAddress?: string,
  ) {
    if (!vxPremiaAddress && (!premiaAddress || !usdcAddress))
      throw new Error(
        "PREMIA and USDC addresses are required if vxPremia address isn't provided",
      );

    // Diamond and facets deployment
    const premiaDiamond = await new Premia__factory(deployer).deploy();
    await updateDeploymentMetadata(
      deployer,
      ContractKey.PremiaDiamond,
      ContractType.DiamondProxy,
      premiaDiamond,
      [],
      { logTxUrl: true },
    );

    //////////////////////////////////////////////

    /////////////////
    // PoolFactory //
    /////////////////

    const placeholder = await new Placeholder__factory(deployer).deploy();
    await placeholder.deployed();
    console.log(`Placeholder : ${placeholder.address}`);

    //////////////////////////////////////////////

    const poolFactoryProxyArgs = [
      placeholder.address,
      discountPerPool.toString(),
      insuranceFund,
    ];
    const poolFactoryProxy = await new PoolFactoryProxy__factory(
      deployer,
    ).deploy(
      poolFactoryProxyArgs[0],
      poolFactoryProxyArgs[1],
      poolFactoryProxyArgs[2],
    );
    await updateDeploymentMetadata(
      deployer,
      ContractKey.PoolFactoryProxy,
      ContractType.Proxy,
      poolFactoryProxy,
      poolFactoryProxyArgs,
      { logTxUrl: true },
    );

    //////////////////////////////////////////////

    const poolFactoryDeployerArgs = [
      premiaDiamond.address,
      poolFactoryProxy.address,
    ];
    const poolFactoryDeployer = await new PoolFactoryDeployer__factory(
      deployer,
    ).deploy(poolFactoryDeployerArgs[0], poolFactoryDeployerArgs[1]);
    await updateDeploymentMetadata(
      deployer,
      ContractKey.PoolFactoryDeployer,
      ContractType.Standalone,
      poolFactoryDeployer,
      poolFactoryDeployerArgs,
      { logTxUrl: true },
    );

    //////////////////////////////////////////////

    const poolFactoryImplArgs = [
      premiaDiamond.address,
      chainlinkAdapter,
      wrappedNativeToken,
      poolFactoryDeployer.address,
    ];
    const poolFactoryImpl = await new PoolFactory__factory(deployer).deploy(
      poolFactoryImplArgs[0],
      poolFactoryImplArgs[1],
      poolFactoryImplArgs[2],
      poolFactoryImplArgs[3],
    );
    await updateDeploymentMetadata(
      deployer,
      ContractKey.PoolFactoryImplementation,
      ContractType.Implementation,
      poolFactoryImpl,
      poolFactoryImplArgs,
      { logTxUrl: true },
    );

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
    const routerArgs = [poolFactory.address];
    const router = await new ERC20Router__factory(deployer).deploy(
      routerArgs[0],
    );
    await updateDeploymentMetadata(
      deployer,
      ContractKey.ERC20Router,
      ContractType.Standalone,
      router,
      routerArgs,
      { logTxUrl: true },
    );

    // ExchangeHelper
    if (!exchangeHelperAddress) {
      const exchangeHelper = await new ExchangeHelper__factory(
        deployer,
      ).deploy();
      await updateDeploymentMetadata(
        deployer,
        ContractKey.ExchangeHelper,
        ContractType.Standalone,
        exchangeHelper,
        [],
        { logTxUrl: true },
      );

      exchangeHelperAddress = exchangeHelper.address;
    }

    // UserSettings
    const userSettingsImpl = await new UserSettings__factory(deployer).deploy();
    await updateDeploymentMetadata(
      deployer,
      ContractKey.UserSettingsImplementation,
      ContractType.Implementation,
      userSettingsImpl,
      [],
      { logTxUrl: true },
    );

    const userSettingsProxyArgs = [userSettingsImpl.address];
    const userSettingsProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(userSettingsProxyArgs[0]);
    await updateDeploymentMetadata(
      deployer,
      ContractKey.UserSettingsProxy,
      ContractType.Proxy,
      userSettingsProxy,
      userSettingsProxyArgs,
      { logTxUrl: true },
    );

    //////////////////////////////////////////////

    // Vault Registry
    const vaultRegistryImpl = await new VaultRegistry__factory(
      deployer,
    ).deploy();
    await updateDeploymentMetadata(
      deployer,
      ContractKey.VaultRegistryImplementation,
      ContractType.Implementation,
      vaultRegistryImpl,
      [],
      { logTxUrl: true },
    );

    const vaultRegistryProxyArgs = [vaultRegistryImpl.address];
    const vaultRegistryProxy = await new ProxyUpgradeableOwnable__factory(
      deployer,
    ).deploy(vaultRegistryProxyArgs[0]);
    await updateDeploymentMetadata(
      deployer,
      ContractKey.VaultRegistryProxy,
      ContractType.Proxy,
      vaultRegistryProxy,
      vaultRegistryProxyArgs,
      { logTxUrl: true },
    );

    //////////////////////////////////////////////

    // VxPremia
    if (!vxPremiaAddress) {
      const vxPremiaImplArgs = [
        constants.AddressZero,
        constants.AddressZero,
        premiaAddress as string, // We already ensured this cant be undefined at the beginning of the function
        usdcAddress as string, // We already ensured this cant be undefined at the beginning of the function
        exchangeHelperAddress,
        vaultRegistryProxy.address,
      ];
      const vxPremiaImpl = await new VxPremia__factory(deployer).deploy(
        vxPremiaImplArgs[0],
        vxPremiaImplArgs[1],
        vxPremiaImplArgs[2],
        vxPremiaImplArgs[3],
        vxPremiaImplArgs[4],
        vxPremiaImplArgs[5],
      );
      await updateDeploymentMetadata(
        deployer,
        ContractKey.VxPremiaImplementation,
        ContractType.Implementation,
        vxPremiaImpl,
        vxPremiaImplArgs,
        { logTxUrl: true },
      );

      const vxPremiaProxyArgs = [vxPremiaImpl.address];
      const vxPremiaProxy = await new VxPremiaProxy__factory(deployer).deploy(
        vxPremiaProxyArgs[0],
      );
      await updateDeploymentMetadata(
        deployer,
        ContractKey.VxPremiaProxy,
        ContractType.Proxy,
        vxPremiaProxy,
        vxPremiaProxyArgs,
        { logTxUrl: true },
      );
      vxPremiaAddress = vxPremiaProxy.address;
    }

    const referralImplArgs = [poolFactory.address];
    const referralImpl = await new Referral__factory(deployer).deploy(
      poolFactory.address,
    );
    await updateDeploymentMetadata(
      deployer,
      ContractKey.ReferralImplementation,
      ContractType.Implementation,
      referralImpl,
      referralImplArgs,
      { logTxUrl: true },
    );

    const referralProxyArgs = [referralImpl.address];
    const referralProxy = await new ReferralProxy__factory(deployer).deploy(
      referralImpl.address,
    );
    await updateDeploymentMetadata(
      deployer,
      ContractKey.ReferralProxy,
      ContractType.Proxy,
      referralProxy,
      referralProxyArgs,
      { logTxUrl: true },
    );

    const referral = IReferral__factory.connect(
      referralProxy.address,
      deployer,
    );

    //////////////////////////////////////////////

    const deployedFacets = await PoolUtil.deployPoolImplementations(
      deployer,
      poolFactory.address,
      router.address,
      userSettingsProxy.address,
      vxPremiaAddress,
      wrappedNativeToken,
      feeReceiver,
      referral.address,
      vaultRegistryProxy.address,
      false,
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
