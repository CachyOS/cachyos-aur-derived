# Maintainer: Owen Trigueros <owentrigueros@gmail.com>

pkgname=httpdirfs
pkgver=1.3.3
pkgrel=1
pkgdesc="A filesystem which allows you to mount HTTP directory listings"
arch=('x86_64')
url="https://github.com/fangfufu/httpdirfs"
license=('GPL')
depends=('gumbo-parser' 'fuse3' 'curl' 'expat' 'util-linux-libs' 'openssl')
makedepends=('meson' 'help2man' 'doxygen' 'graphviz')
source=("$pkgname-$pkgver.tar.gz::https://github.com/fangfufu/$pkgname/archive/$pkgver.tar.gz"
         "httpdirfs.patch")
md5sums=("61cd87fde28aeaec7d39e38f533dc058"
         "068486cabbb5818ba1e019976f2ed340")

prepare() {
  cd $pkgname-$pkgver
  patch -Np1 -i ../httpdirfs.patch
}

build() {
  arch-meson "$pkgname-$pkgver" build -Dc_args="-std=gnu17"
  meson compile -C build
}

package() {
  meson install -C build --destdir "$pkgdir"
}
