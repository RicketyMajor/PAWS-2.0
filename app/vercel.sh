#!/bin/bash

# Este script descarga Flutter y compila la versión Web en el entorno de Vercel

echo "Clonando el SDK de Flutter (rama stable)..."
git clone https://github.com/flutter/flutter.git -b stable --depth 1

echo "Añadiendo Flutter al PATH..."
export PATH="$PATH:`pwd`/flutter/bin"

echo "Instalando dependencias de Flutter..."
flutter pub get

echo "Construyendo la versión Web..."
flutter build web --release

echo "¡Build completado!"
