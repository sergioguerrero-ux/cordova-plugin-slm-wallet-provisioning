# Debug Google Pay - Verificación de Tarjetas

## Problema
El verificador de tarjetas se queda atascado en "Verificando Google Pay..." cuando intenta verificar si una tarjeta existe en Google Wallet.

## Flujo de Comunicación

```
servidor/google-pay-flow.js (checkCardsInWallet)
    ↓ llama slmwafk.isCardInGoogleWallet()
servidor/slmwafk.js (isCardInGoogleWallet)
    ↓ webkit.messageHandlers.cordova_iab.postMessage
monaca/slmwafk.js (isCardInGoogleWallet)
    ↓ cordova.exec()
src/android/SLMWalletProvisioning.java (execute → isCardInGoogleWallet)
    ↓ tapAndPayClient.listTokens()
    ↓ callbackContext.success()
monaca/slmwafk.js (success callback)
    ↓ _inAppBrowser.executeScript()
servidor/slmwafk.js (_slm_resolvePromise)
    ↓ resolve(data)
servidor/google-pay-flow.js (recibe resultado)
```

## Logs Agregados

### 1. servidor/google-pay-flow.js
- ✅ Logs en `checkCardsInWallet()` antes y después de cada verificación
- ✅ Alerts para debugging en tiempo real
- ✅ Logs del resultado recibido

### 2. servidor/slmwafk.js
- ✅ Logs en `isCardInGoogleWallet()` al inicio
- ✅ Logs del promise ID
- ✅ Logs del callback cuando se recibe la respuesta
- ✅ Alerts en cada paso

### 3. monaca/slmwafk.js
- ✅ Logs en `isCardInGoogleWallet()` al recibir el mensaje
- ✅ Logs antes y después de llamar cordova.exec
- ✅ Logs en success y error callbacks
- ✅ Alerts en cada paso

### 4. src/android/SLMWalletProvisioning.java
- ✅ Logs extensivos en `execute()` para identificar la acción
- ✅ Logs en `isCardInGoogleWallet()` en cada paso:
  - Inicio del método
  - Dentro del thread pool
  - Llamada a listTokens()
  - Success callback con cada token
  - Resultado final antes de llamar callbackContext.success()
  - Failure callback con detalles del error

## Cómo Usar los Logs

1. **Compilar la app con Monaca.io**
   ```bash
   # Asegurarse de que los cambios estén subidos
   git add .
   git commit -m "feat: Add extensive logging for Google Wallet verification"
   ```

2. **Ejecutar en dispositivo Android**
   - Conectar dispositivo via USB
   - Habilitar USB Debugging
   - Ejecutar: `adb logcat -s WalletProvisioning:D *:E`

3. **Ver logs en consola del navegador**
   - Los alerts aparecerán en pantalla
   - Los console.log se verán en las DevTools si están habilitadas

## Posibles Causas del Problema

### Causa 1: TapAndPayClient no inicializado
**Síntoma**: No se ve el log "tapAndPayClient creado: true"
**Solución**: Verificar que los servicios de Google Play están disponibles

### Causa 2: cordova.exec no responde
**Síntoma**: Se ve el log "[MONACA] Llamando cordova.exec..." pero nunca llega "[MONACA] cordova.exec SUCCESS"
**Solución**:
- Verificar que el plugin está instalado correctamente
- Verificar que el nombre del plugin es "WalletProvisioning" (no "SLMWalletProvisioning")

### Causa 3: execute() no reconoce la acción
**Síntoma**: Se ve "Accion NO RECONOCIDA: isCardInGoogleWallet"
**Solución**: Verificar el nombre de la acción en plugin.xml

### Causa 4: listTokens() falla
**Síntoma**: Se ve "listTokens FAILURE" en logs
**Soluciones**:
- App no está registrada con Google Pay
- Permisos faltantes
- Google Play Services desactualizados

### Causa 5: Callback no se ejecuta en IAB
**Síntoma**: Se ve "[MONACA] Ejecutando en IAB..." pero el servidor nunca recibe la respuesta
**Solución**: Verificar que _inAppBrowser existe y está listo

## Checklist de Verificación

- [ ] Los logs de Android muestran "EXECUTE LLAMADO"
- [ ] Los logs de Android muestran "Accion isCardInGoogleWallet detectada"
- [ ] Los logs de Android muestran "listTokens() llamado (async)"
- [ ] Los logs de Android muestran "listTokens SUCCESS" o "listTokens FAILURE"
- [ ] Los logs de Android muestran "callbackContext.success() llamado"
- [ ] Los logs de Monaca muestran "cordova.exec SUCCESS"
- [ ] Los logs de Monaca muestran "Ejecutando en IAB"
- [ ] Los logs del servidor muestran "isCardInGoogleWallet callback recibido"
- [ ] Los logs del servidor muestran resultado final

## Comandos Útiles

```bash
# Ver logs en tiempo real (Android)
adb logcat -s WalletProvisioning:D *:E

# Limpiar logs
adb logcat -c

# Ver logs solo de isCardInGoogleWallet
adb logcat -s WalletProvisioning:D | grep "isCardInGoogleWallet"

# Guardar logs a archivo
adb logcat -s WalletProvisioning:D *:E > debug_logs.txt
```

## Próximos Pasos

1. Ejecutar la app con los logs habilitados
2. Identificar en qué punto se detiene el flujo
3. Según el punto donde se detiene, aplicar la solución correspondiente
4. Una vez resuelto, se pueden remover los alerts (dejar solo console.log)
