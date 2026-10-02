/* dlopen every .eln below the given directories, once, so macOS's
   first-load check is paid here instead of inside Emacs. Errors are
   ignored: a file that fails to load is one Emacs would not load either. */
#include <dlfcn.h>
#include <ftw.h>
#include <string.h>

static int one(const char *path, const struct stat *st, int type, struct FTW *ftw) {
  size_t n = strlen(path);
  (void)st; (void)ftw;
  if (type == FTW_F && n > 4 && strcmp(path + n - 4, ".eln") == 0) {
    void *h = dlopen(path, RTLD_LAZY | RTLD_LOCAL);
    if (h) dlclose(h);
  }
  return 0;
}

int main(int argc, char **argv) {
  for (int i = 1; i < argc; i++) nftw(argv[i], one, 16, FTW_PHYS);
  return 0;
}
