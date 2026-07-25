output "peering_connection_ids" {
  description = "Peering connection IDs keyed by \"<region-a>-to-<region-b>\"."
  value       = { for k, v in aws_vpc_peering_connection.this : k => v.id }
}

output "peered_region_pairs" {
  description = "The region pairs this mesh connects. Exposed so tests can assert topology without applying."
  value       = local.pairs
}
