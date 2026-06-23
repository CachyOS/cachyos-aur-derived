# Maintainer: Alexander Courtis <alex@courtis.org>
pkgname=way-displays
pkgver=1.15.0
pkgrel=2
pkgdesc="way-displays: Auto Manage Your Wayland Displays"
arch=('x86_64')
url="https://github.com/alex-courtis/way-displays"
license=('MIT')
depends=('wayland' 'wlroots0.18' 'libinput' 'yaml-cpp')
makedepends=('git' 'make' 'gcc')
source=("https://github.com/alex-courtis/${pkgname}/archive/refs/tags/${pkgver}.tar.gz")
sha256sums=('8ef741fd2f0452098e5a3d0131013b8c0ea6bdb11ed85d1e39c34c05c0d353d6')
install=way-displays.install

build() {
	cd "$pkgname-$pkgver"
	make CC=gcc CXX=g++ way-displays
}

package() {
	cd "$pkgname-$pkgver"
	make PREFIX="/usr" PREFIX_ETC="" DESTDIR="$pkgdir" install
}

