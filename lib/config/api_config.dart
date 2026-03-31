class ApiConfig {
  // URL del backend API
  // En desarrollo local: usar la IP de la maquina (no localhost)
  // En produccion: https://api.tudominio.com/api
  static const String baseUrl =
      'http://soportetecnico-backend-xlufk1-ce8600-187-124-247-144.traefik.me/api';

  // URL publica donde el cliente consulta el estado escaneando el QR
  // Debe ser accesible desde el celular del cliente en la misma red
  // En produccion: https://soporte.tudominio.com
  static const String statusPageUrl =
      'http://soportetecnico-backend-xlufk1-ce8600-187-124-247-144.traefik.me';
}
