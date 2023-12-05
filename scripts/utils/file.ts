import fs from 'fs';
import path from 'path';
import { ContractType } from './deployment/types';

export function getContractFilePaths(
  rootPath: string = './contracts',
  contractFilePaths: string[] = [],
) {
  for (const file of fs.readdirSync(rootPath)) {
    const absolutePath = path.join(rootPath, file).replaceAll('\\', '/');

    if (fs.statSync(absolutePath).isDirectory()) {
      contractFilePaths = getContractFilePaths(absolutePath, contractFilePaths);
    }

    contractFilePaths.push(absolutePath);
  }

  return contractFilePaths;
}

export function getContractFilePath(
  contractName: string,
  contractFilePaths: string[],
): string {
  for (const contractFilePath of contractFilePaths) {
    const contractFileNameWithExtension =
      contractFilePath.replaceAll('\\', '/').split('/').pop() ?? '';

    if (contractFileNameWithExtension.split('.')[0] === contractName)
      return contractFilePath;
  }

  return '';
}

export function inferContractName(
  contractKey: string,
  contractType: ContractType | string,
) {
  const override = NameOverride[contractKey];
  if (override) return override;

  let name = addSpaceBetweenUpperCaseLetters(contractKey);
  // remove the contract type from the name, if it's there
  const typeInName = name.split(' ').pop() === contractType;

  if (typeInName) return name.split(' ').slice(0, -1).join('');
  return name.split(' ').join('');
}

export function inferContractDescription(
  contractKey: string,
  contractType: ContractType | string,
) {
  const override = DescriptionOverride[contractKey];
  if (override) return override;

  let name = addSpaceBetweenUpperCaseLetters(contractKey);
  // remove the contract type from the name, if it's there
  const typeInName = name.split(' ').pop() === contractType;

  if (typeInName) name = name.split(' ').slice(0, -1).join(' ');
  const type = addSpaceBetweenUpperCaseLetters(contractType);
  return `${name} ${type}`;
}

function addSpaceBetweenUpperCaseLetters(s: string) {
  return s.replace(/([a-z])([A-Z])/g, '$1 $2');
}

export const NameOverride: { [key: string]: string } = {
  PremiaDiamond: 'Premia',
  VxPremiaProxy: 'VxPremiaProxy',
  OptionPSImplementation: 'OptionPS',
  OptionPSFactoryImplementation: 'OptionPSFactory',
  ReferralProxy: 'ReferralProxy',
  VaultMiningProxy: 'VaultMiningProxy',
  PoolFactoryProxy: 'PoolFactoryProxy',
  OptionPSFactoryProxy: 'ProxyUpgradeableOwnable',
  ChainlinkAdapterProxy: 'ProxyUpgradeableOwnable',
  UserSettingsProxy: 'ProxyUpgradeableOwnable',
  VaultRegistryProxy: 'ProxyUpgradeableOwnable',
  VolatilityOracleProxy: 'ProxyUpgradeableOwnable',
  OptionRewardFactoryProxy: 'ProxyUpgradeableOwnable',
  PaymentSplitterProxy: 'ProxyUpgradeableOwnable',
};

export const DescriptionOverride: { [key: string]: string } = {
  PremiaDiamond: 'Premia Diamond Proxy',
  VxPremiaImplementation: 'vxPREMIA Implementation',
  VxPremiaProxy: 'vxPREMIA Proxy',
  OptionPSImplementation: 'Option Physically Settled Implementation',
  OptionPSFactoryImplementation:
    'Option Physically Settled Factory Implementation',
  OptionPSFactoryProxy: 'Option Physically Settled Factory Proxy',
  PaymentSplitterProxy: 'Payment Splitter Proxy',
};
