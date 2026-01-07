#!/usr/bin/env node

/**
 * Hook para agregar los entitlements de Apple Pay Provisioning
 * Este hook se ejecuta después de que se agrega la plataforma iOS
 */

const fs = require('fs');
const path = require('path');
const plist = require('plist');

module.exports = function (context) {
    const platforms = context.opts.platforms || [];

    // Solo ejecutar para iOS
    if (platforms.indexOf('ios') === -1) {
        return;
    }

    console.log('[SLM Wallet] Configurando entitlements de Apple Pay...');

    const projectRoot = context.opts.projectRoot;
    const iosPath = path.join(projectRoot, 'platforms', 'ios');

    // Buscar el archivo .xcodeproj
    const files = fs.readdirSync(iosPath);
    const xcodeprojFile = files.find(f => f.endsWith('.xcodeproj'));

    if (!xcodeprojFile) {
        console.error('[SLM Wallet] ERROR: No se encontró el archivo .xcodeproj');
        return;
    }

    const projectName = xcodeprojFile.replace('.xcodeproj', '');
    console.log('[SLM Wallet] Nombre del proyecto:', projectName);

    // Crear archivos de entitlements para Debug y Release
    const debugEntitlementsPath = path.join(iosPath, projectName, `${projectName}-Debug.entitlements`);
    const releaseEntitlementsPath = path.join(iosPath, projectName, `${projectName}-Release.entitlements`);

    // Contenido del entitlement
    const entitlements = {
        'com.apple.developer.payment-pass-provisioning': ['$(CFBundleIdentifier)']
    };

    // Función para crear o actualizar entitlements
    function updateEntitlements(filePath) {
        let existingEntitlements = {};

        // Si el archivo existe, leerlo
        if (fs.existsSync(filePath)) {
            console.log('[SLM Wallet] Leyendo archivo existente:', filePath);
            try {
                const content = fs.readFileSync(filePath, 'utf8');
                existingEntitlements = plist.parse(content);
            } catch (e) {
                console.log('[SLM Wallet] No se pudo leer el archivo existente, creando uno nuevo');
            }
        }

        // Agregar o actualizar el entitlement
        existingEntitlements['com.apple.developer.payment-pass-provisioning'] = ['$(CFBundleIdentifier)'];

        // Escribir el archivo
        const plistContent = plist.build(existingEntitlements);
        fs.writeFileSync(filePath, plistContent, 'utf8');
        console.log('[SLM Wallet] ✓ Entitlements actualizados:', filePath);
    }

    // Crear/actualizar ambos archivos
    updateEntitlements(debugEntitlementsPath);
    updateEntitlements(releaseEntitlementsPath);

    // Ahora necesitamos actualizar el proyecto Xcode para usar estos archivos
    const xcodeprojPath = path.join(iosPath, xcodeprojFile, 'project.pbxproj');

    if (fs.existsSync(xcodeprojPath)) {
        console.log('[SLM Wallet] Actualizando configuración de build...');

        let pbxproj = fs.readFileSync(xcodeprojPath, 'utf8');

        // Agregar CODE_SIGN_ENTITLEMENTS para Debug
        if (pbxproj.indexOf(`CODE_SIGN_ENTITLEMENTS = "${projectName}/${projectName}-Debug.entitlements"`) === -1) {
            pbxproj = pbxproj.replace(
                /buildSettings = \{([^}]*name = Debug[^}]*)\}/g,
                function (match, p1) {
                    if (match.indexOf('CODE_SIGN_ENTITLEMENTS') === -1) {
                        return match.replace(
                            'buildSettings = {',
                            `buildSettings = {\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = "${projectName}/${projectName}-Debug.entitlements";`
                        );
                    }
                    return match;
                }
            );
        }

        // Agregar CODE_SIGN_ENTITLEMENTS para Release
        if (pbxproj.indexOf(`CODE_SIGN_ENTITLEMENTS = "${projectName}/${projectName}-Release.entitlements"`) === -1) {
            pbxproj = pbxproj.replace(
                /buildSettings = \{([^}]*name = Release[^}]*)\}/g,
                function (match, p1) {
                    if (match.indexOf('CODE_SIGN_ENTITLEMENTS') === -1) {
                        return match.replace(
                            'buildSettings = {',
                            `buildSettings = {\n\t\t\t\tCODE_SIGN_ENTITLEMENTS = "${projectName}/${projectName}-Release.entitlements";`
                        );
                    }
                    return match;
                }
            );
        }

        fs.writeFileSync(xcodeprojPath, pbxproj, 'utf8');
        console.log('[SLM Wallet] ✓ Configuración de build actualizada');
    }

    console.log('[SLM Wallet] ✓ Entitlements de Apple Pay configurados correctamente');
};