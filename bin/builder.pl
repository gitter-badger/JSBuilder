#!/usr/bin/perl

use Mojolicious::Lite;
use YAML qw/LoadFile/;
use JavaScript::Minifier qw/minify/;
#use App::gh::Git;
use Mojo::JSON;
use FindBin qw/$Bin/;
use File::Copy::Recursive qw/dircopy/;

my $projects_dir  = "./projects";
my $cache_dir     = "./cache";
my $project_skell = "./pskell";

my $repo_dir = $projects_dir;

chdir "$Bin/../";
my $json = Mojo::JSON->new;

unless(-d $projects_dir) {
   mkdir($projects_dir);
}
unless(-d $project_skell) {
   mkdir($project_skell);
}
unless(-d $cache_dir) {
   mkdir($cache_dir);
}

app->static->root($cache_dir);

any "/create_new_project/:proj_name" => sub {
   my $self = shift;
   my $proj = $self->param("proj_name");

   return $self->render(code => 300) if not $self->create_new_project_dir($proj);
   my $server = $self->tx->local_address . ":" . $self->tx->local_port;
   return $self->render(text => "http://$server/$repo_dir/$proj");
} => undef;

any "/get_code_from/:proj_name" => sub {
   my $self      = shift;
   my $proj      = $self->param("proj_name");
   my $init_conf = eval q/$json->decode($self->param("asking"))/;
   $self->stash->{atual_project} = $proj;
   my $code = $self->get_all_code($proj, $init_conf);
   unless(-d "$cache_dir/get_code_from") {
      mkdir("$cache_dir/get_code_from");
   }
   open my $cache, ">", "$cache_dir/get_code_from/$proj";
   print { $cache } $code;
   $self->render(text => $code);
};

helper create_new_project_dir => sub {
   my $self = shift;
   my $proj = shift;

   return 0 if -d "$projects_dir/$proj";

   if(dircopy($project_skell, "$projects_dir/$proj")) {
      chdir "$projects_dir/$proj";
      #Git::command_noisy("init");
      #my $repo = Git->repository (Directory => '.');
      #$repo->command("add", ".");
      #$repo->command("commit", "-a -m 'Initial Commit (JSBuilder)'");
      qx{git init};
      qx{git add .};
      qx{git commit -a -m "Initial Commit (JSBuilder)"};
      return 1;
   }
   return 0;
};

helper get_project_code => sub {
   my $self = shift;
   my $proj = shift;

   my $code;
   for my $file($self->get_project_files($proj)) {
      $code .= $self->get_code($proj, $file);
   }
   $code
};

helper get_all_code => sub{
   my $self      = shift;
   my $proj      = shift;
   my $init_conf = shift;

   my @projs = $self->get_dependency_list($proj);
   app->log->debug(@projs);

   my $code = $self->get_code_from_file("./js/ObjectLifeCicleManager.js");
   my $json_conf = $json->encode($self->get_all_conf($proj, $init_conf));
   $code .= "$/$/\$IOC = new  ObjectLifeCicleManager($json_conf);$/$/";

   for my $dproj($self->get_dependency_list($proj)) {
      for my $pfile ($self->get_project_files($dproj)) {
         $code .= $self->get_code($dproj, $pfile);
      }
   }
   for my $pfile ($self->get_project_files($proj)) {
      $code .= $self->get_code($proj, $pfile);
   }
   $code;
};

helper get_all_conf => sub {
   my $self      = shift;
   my $project   = shift;
   my $init_conf = shift;

   my $conf;
   for my $dproj($self->get_dependency_list($project)) {
      my $tmp_conf = $self->get_all_conf($dproj);
      for my $key(keys %$tmp_conf) {
         $conf->{$key} = $tmp_conf->{$key};
      }
   }
   my $tmp_conf = $self->get_project_conf($project);
   for my $key(keys %$tmp_conf) {
      $conf->{$key} = $tmp_conf->{$key};
   }
   if(defined $init_conf and ref $init_conf eq "HASH") {
      for my $key(keys %$init_conf) {
         $conf->{$key} = $init_conf->{$key};
      }
   }
   $conf
};

helper get_project_conf => sub {
   my $self    = shift;
   my $project = shift;

   return unless exists $self->get_project_details($project)->{asking};
   $self->get_project_details($project)->{asking};
};

helper should_be_showed => sub {
   my $self    = shift;
   my $project = shift;
   my $file    = shift;

   my $donot = $self->get_project_details($project)->{"do not export"};
   for my $test(ref $donot eq "ARRAY" ? @$donot : $donot) {
      return 1 if $file eq $test;
   }
   return 0;
};

helper get_code => sub{
   my $self    = shift;
   my $project = shift;
   my $file    = shift;

   if($project ne $self->stash->{atual_project}) {
      return if $self->should_be_showed($project, $file);
   }
   my $pdir = $self->get_project_dir($project);
   $self->get_code_from_file("$pdir/$file");
};

helper get_code_from_file => sub{
   my $self    = shift;
   my $file    = shift;

   open(my $fh, "<", "$file") || die "File '$file' not found.";
   minify(input => $fh, copyright => "$file")
};

helper get_dependency_list => sub{
   my $self = shift;
   my $proj = shift;

   my @dep;
   if(exists $self->get_project_details($proj)->{depends} and ref $self->get_project_details($proj)->{depends} eq "ARRAY") {
      my @primary_dep = @{ $self->get_project_details($proj)->{depends} };
      my %udep = map {($_ => 1)} @primary_dep;
      for my $sub_dep(@primary_dep) {
         for my $d($self->get_dependency_list($sub_dep)){
            push @dep, $d if not exists $udep{$d};
            $udep{$d}++;
         }
      }
      push @dep, @primary_dep;
   }
   @dep
};

helper get_project_files => sub {
   my $self    = shift;
   my $project = shift;

   @{ $self->get_project_details($project)->{files} };
};

helper get_project_dir => sub {
   my $self    = shift;
   my $project = shift;

   app->log->debug("$projects_dir/$project");
   "$projects_dir/$project";
};

helper get_project_details => sub{
   my $self = shift;
   my $name = shift;

   if(-f "$projects_dir/$name/project.yaml") {
      return LoadFile("$projects_dir/$name/project.yaml");
   } elsif(-f "$projects_dir/$name/project.json") {
      open my $filejson, "<", "$projects_dir/$name/project.json";
      return $json->decode(join "", <$filejson>);
   } else {
      return { files => [ map {s{^$projects_dir/$name/}{}; $_} <$projects_dir/$name/*.js> ] }
   }
};

app->start("daemon");
