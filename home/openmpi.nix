{ pkgs, ... }:

let
  jdk = pkgs.jdk;

  # nixpkgs builds Open MPI without the Java bindings; enable them so that
  # `mpijavac` and `lib/mpi.jar` are available.
  openmpiJava = pkgs.openmpi.overrideAttrs (old: {
    pname = "openmpi-java";

    nativeBuildInputs = old.nativeBuildInputs ++ [ jdk ];

    configureFlags = old.configureFlags ++ [
      "--enable-mpi-java"
      "--with-jdk-dir=${jdk.home}"
    ];

    # Java bindings are not covered by the upstream test suite and slow it down.
    doCheck = false;

    # mpijavac is a Perl script installed with `#!/usr/bin/env perl`.
    postFixup = old.postFixup + ''
      substituteInPlace $out/bin/mpijavac.pl \
        --replace-fail "#!/usr/bin/env perl" "#!${pkgs.perl}/bin/perl"
    '';
  });
in
{
  home.packages = [
    jdk
    openmpiJava
  ];

  home.sessionVariables = {
    JAVA_HOME = "${jdk.home}";
    MPI_JAR = "${openmpiJava}/lib/mpi.jar";
  };
}
