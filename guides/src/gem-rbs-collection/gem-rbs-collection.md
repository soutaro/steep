# Using RBS from gem_rbs_collection

gem_rbs_collection is a repository of type definitions of gems that are managed by the community. You may find the type definition of a gem that ships without RBS type definitions.

To use RBS files from the repository, you can use rbs-collection subcommand. This guide explains how the command works.

## Quick start

Run rbs-collection-init to start setup.

```
$ rbs collection init
```

You have to edit your `Gemfile`. Specify `require: false` for gems for which you do not want type definitions.

```ruby
gem 'rbs', require: false
gem 'steep', require: false
gem 'rbs_rails', require: false
gem 'rbs_protobuf', require: false
```

Once you save the file, run the install command.

```
$ rbs collection install
```

That generates `rbs_collection.lock.yaml` and downloads the RBS files from the git repository.

Note that rbs-collection automatically downloads RBS files of gems included in your Bundler environment. You don't have to write all of the gems in your `Gemfile` in `rbs_collection.yaml`.

Finally, we recommend adding the `rbs_collection.yaml` and `rbs_collection.lock.yaml` to your repository, and ignoring `.gem_rbs_collection` directory.

```
$ git add rbs_collection.yaml
$ git add rbs_collection.lock.yaml
$ echo /.gem_rbs_collection >> .gitignore
$ git commit -m "Set up rbs-collection"
```

## Updating RBS files

You may want to run rbs-collection-update to update the contents of `rbs_collection.lock.yaml`, when you add a new gem or some gems are updated.

You also need to run rbs-collection-update when the RBS files in the source repository are updated. The type definitions are updated with bug-fixes or improvements, and you need to update to apply the changes to your app.

## Using rbs-collection with Steep

Steep automatically reads `rbs_collection.yaml`. You can use Steep immediately without any modifications.

```
$ bin/steep project    # Show dependencies detected by Steep
$ bin/steep check      # Run type check
```

## Migration

If you have used older versions of Steep or RBS, you may have configured libraries manually.

* You have library calls in `Steepfile`
* You have git submodules in your git repository to download gem_rbs_collection

These are steps to migrate to rbs-collection.

1. Remove unnecessary library configuration
2. Set up rbs-collection
3. Validate the configuration
4. Delete submodule

### 1. Remove unnecessary library configurations

You may have `#library` calls in your Steepfile, or something equivalent in your scripts. We can group the configured libraries into three groups.

1. Gems that is managed by Bundler
2. Standard libraries (non-gem libs, default gems, and bundled gems)
    * 2-1) That is a transitive dependency from libraries in group 1
    * 2-2) That is included in Gemfile.lock
    * 2-3) Implicitly installed gems – not included in Gemfile

You can delete library configs of 1, 2-1, and 2-2. So, you have to keep the configurations of libraries in 2-3.

Practically, you can remove all library configs and `#library` calls in `Steepfile`, go step 2, run steep check to test, and restore the configs of libraries if error is detected.

### 2. Set up rbs-collection

See the quick start section above!

### 3. Validate the configuration

Run steep check to validate the configuration.

```
$ bin/steep check
```

You may see the `UnknownTypeName` error if some libraries are missing. Or some errors that implies duplication or inconsistency of methods/class/module definitions, that may be caused by loading RBS files of a library twice.

Running steep project may help you too. It shows the source files and library directories recognized by Steep.

```
$ bin/steep project
```

Note that the type errors detected may change after migrating to rbs-collection, because it typically includes updating to newer versions of RBS files.

### 4. Delete submodule

After you confirmed everything is working correctly, you can delete the submodule. deinit the submodule, remove the directory using git-rm, and delete $GIT_DIR/modules/<name>/.

## What is the rbs_collection.yaml file?

The file mainly defines three properties – sources, gems and path. Sources is essential when you want to create a new RBS file repository, usually for RBS files of the private gems.

Another trick is ignoring RBS files of type checker toolchain. RBS and Steep ships with their own RBS files. However, these RBS files may be unnecessary for you, unless you are not a type checking toolchain developer. It requires some additional gems and RBS files. So adding ignore: true is recommended for the gems.

It seems like we need to add a feature to skip loading RBS files automatically and use the feature for RBS, Steep, and RBS Rails. It looks weird that the gems section is only used to ignore gems.

## Versions of RBS files in gem_rbs_collection

Gem versions in rbs-collection are relatively loosely managed. If a gem is found but the version is different, rbs-collection simply uses the incorrect version.

It will load RBS files of activerecord/6.1 even if your Gemfile specifies activerecord-7.0.4. This is by design with an assumption that having RBS files with some incompatibility is better than having nothing. We see most APIs are compatible even after major version upgrade. Dropping everything for minor API incompatibilities would not make much sense.

That behavior will change in future versions when we see that the assumption is not reasonable and we have better coverage.
