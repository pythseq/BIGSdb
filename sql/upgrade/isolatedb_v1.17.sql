ALTER TABLE isolate_field_extended_attributes DROP CONSTRAINT isolate_field_extended_attributes_pkey;
ALTER TABLE isolate_field_extended_attributes ADD PRIMARY KEY(attribute);
ALTER TABLE isolate_value_extended_attributes DROP CONSTRAINT isolate_value_extended_attributes_pkey;
ALTER TABLE isolate_value_extended_attributes ADD PRIMARY KEY (attribute,field_value);
