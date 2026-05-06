import * as fs from 'fs';
import * as path from 'path';

const CONFIG_PATH = 'C:\\Users\\Reno\\.openclaw\\openclaw.json';

export async function getConfig() {
    try {
        const data = fs.readFileSync(CONFIG_PATH, 'utf8');
        return JSON.parse(data);
    } catch (e) {
        console.error('Failed to read config:', e);
        throw e;
    }
}

export async function setConfig(patch: any) {
    const config = await getConfig();
    
    // Deep merge patch into config
    const merge = (target: any, source: any) => {
        for (const key in source) {
            if (source[key] instanceof Object && key in target) {
                merge(target[key], source[key]);
            } else {
                target[key] = source[key];
            }
        }
    };
    
    merge(config, patch);
    
    try {
        fs.writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2), 'utf8');
        return { success: true };
    } catch (e) {
        console.error('Failed to write config:', e);
        throw e;
    }
}

export async function getModelAliases() {
    const config = await getConfig();
    return config.agents?.defaults?.models || {};
}

export async function setPrimaryModel(modelId: string) {
    return await setConfig({
        agents: {
            defaults: {
                model: {
                    primary: modelId
                }
            }
        }
    });
}
