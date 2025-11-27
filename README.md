# KipuBankV3

Mejoras implementadas

Las mejoras principales incluyen:

✔ Seguridad fortalecida

Para evitar ataques  de reentrada en depósitos y retiros el uso de ReentrancyGuard 

Validaciones con errores personalizados, lo que reduce gas y mejora la trazabilidad.

Bloqueo del fallback y receive para evitar transferencias directas no autorizadas.

Aprobaciones SafeERC20 reseteadas a 

Límites de retiro para reducir impacto de robos

Cap global del banco, evitando que el contrato maneje más fondos de lo previsto.

✔ Mejora en la gestión de tokens

Sistema de whitelist: solo tokens soportados pueden depositarse.

✔ Depósitos más robustos

Conversión automática a USDC para todos los tokens soportados.

Slippage controlado mediante amountOutMin.

Cuenta de depósitos y retiros por usuario para auditorías internas.

✔ Optimización gas / storage

Uso de unchecked cuando es seguro.

Cálculo incremental de saldos y contadores.

Variables inmutable para reducir costos de lectura.

🚀  Instrucciones de Despliegue

📌  Requisitos

Node.js ≥ 18

Hardhat 

📌 Despliegue con Hardhat

npx hardhat run scripts/deploy.js --network sepolia

Interacción con el contrato

📌 Agregar token soportado

 BANK_MANAGER:

supportToken(0xTokenAddress);

📌 Depositar ETH

deposit(address(0), 0, amountOutMin, { value: ethAmount });

📌 Depositar ERC20

deposit(token, amount, amountOutMin);

📌 Retirar USDC

withdraw(usdcAmount);

⚙️ Decisiones de diseño y Trade-offs

✔ Conversión automática a USDC

Motivo: simplicidad contable y estabilidad.

Trade-off: conversión depende del slippage 

✔ Cap bancario global

Controla el TVL máximo para evitar riesgo sistémico.

Trade-off: requiere ajustar manualmente según crecimiento del protocolo.

✔ Rol BANK_MANAGER en lugar de múltiples roles

Reduce complejidad del sistema de permisos.

Trade-off: requiere confianza en el rol.

✔ Sin multicollateral interno

Se convierte todo a un único activo (USDC).

Trade-off: menos flexibilidad pero menor riesgo.

✔ Uso de Uniswap V2

Simplicidad, amplia compatibilidad.

Trade-off: no usa mejoras de V3 como rangos concentrados.

➤ Análisis de Amenazas

Se identifica riesgos actuales y pasos para madurez productiva.

➤ Identificación de debilidades del protocolo

1️ Dependencia del Router Uniswap V2

Un router malicioso o no oficial puede robar fondos.

Mitigación:
✔ Validar router en testnets y producción.
✔ Usar routers verificados únicamente.

2️ Volatilidad durante la conversión

Si el token es muy volátil, el slippage puede causar pérdidas.

Mitigación:
✔ amountOutMin exige slippage controlado.
✔ Se podría implementar un oráculo en el futuro.

3️ Riesgo de aprobación de tokens no estándar

Algunos tokens (USDT) requieren patrones especiales.

Mitigación:
✔ SafeERC20 reduce riesgos.
✔ El contrato resetea approve 

4️ No hay pausability

En emergencias no existe método pause().

Mitigación recomendada:

➤ Implementar Pausable en versión futura.

5️ Dependencia en la autoridad BANK_MANAGER

Es un rol privilegiado poderoso.

Mitigacion Recomendada:
Auditoría interna de permisos.

Pasos faltantes antes de llegar a producción

-Auditoría externa (CertiK / Zellic / OpenZeppelin).

-Implementación de pausability.

-Integración de un oráculo de precios para validar rutas de conversión.

-Pruebas de fuzzing más amplias.

-Simulaciones de MEV 

