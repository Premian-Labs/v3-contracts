export const tableTemplateNoHeader = `# {{chain}} : {{name}} Deployments
|Contract      |Description|Address|    |
|--------------|-----------|-------|----|
{{#sections}}
{{>partial}}
{{/sections}}`;

export const summaryPartial = `{{#contracts}}|\`{{{name}}}\`|{{description}}|{{{displayAddress}}}|{{{displayEtherscanUrl}}}|\n{{/contracts}}`;

export const tableTemplate = `# {{chain}} : {{name}} Deployments
|Contract      |Description|Address|    |    |
|--------------|-----------|-------|----|----|
{{#sections}}
{{displayHeader}}
{{>partial}}
{{/sections}}`;

export const detailedSummaryPartial = `{{#contracts}}|\`{{{name}}}\`|{{description}}|{{{displayAddress}}}|{{{displayEtherscanUrl}}}|{{{displayFilePathUrl}}}|\n{{/contracts}}`;
