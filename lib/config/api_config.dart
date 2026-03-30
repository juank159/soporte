class ApiConfig {
  // URL del backend API
  // En desarrollo local: usar la IP de la maquina (no localhost)
  // En produccion: https://api.tudominio.com/api
  static const String baseUrl = 'http://192.168.1.249:3000/api';

  // URL publica donde el cliente consulta el estado escaneando el QR
  // Debe ser accesible desde el celular del cliente en la misma red
  // En produccion: https://soporte.tudominio.com
  static const String statusPageUrl = 'http://192.168.1.249:3000';
}
