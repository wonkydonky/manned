ALTER TABLE packages DROP CONSTRAINT packages_system_fkey, ADD CONSTRAINT packages_system_fkey FOREIGN KEY(system) REFERENCES systems(id) ON DELETE CASCADE;
ALTER TABLE package_versions DROP CONSTRAINT package_versions_package_fkey, ADD CONSTRAINT package_versions_package_fkey FOREIGN KEY(package) REFERENCES packages(id) ON DELETE CASCADE;
ALTER TABLE man DROP CONSTRAINT man_package_fkey, ADD CONSTRAINT man_package_fkey FOREIGN KEY(package) REFERENCES package_versions(id) ON DELETE CASCADE;
