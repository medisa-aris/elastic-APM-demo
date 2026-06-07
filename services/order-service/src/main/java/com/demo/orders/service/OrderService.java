package com.demo.orders.service;

import com.demo.orders.model.Order;
import com.demo.orders.repository.OrderRepository;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import java.util.List;
import java.util.Map;

@Service
public class OrderService {

    private final OrderRepository repository;
    private final ObjectMapper objectMapper;

    public OrderService(OrderRepository repository, ObjectMapper objectMapper) {
        this.repository = repository;
        this.objectMapper = objectMapper;
    }

    public Order createOrder(List<Map<String, Object>> items, String paymentId, Double totalAmount) {
        Order order = new Order();
        try {
            order.setItems(objectMapper.writeValueAsString(items));
        } catch (JsonProcessingException e) {
            order.setItems("[]");
        }
        order.setPaymentId(paymentId);
        order.setStatus("CONFIRMED");
        order.setTotalAmount(totalAmount);
        return repository.save(order);
    }

    public Order getOrder(String id) {
        return repository.findById(id)
            .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Order not found: " + id));
    }

    public List<Order> getAllOrders() {
        return repository.findAllByOrderByCreatedAtDesc();
    }

    public Order refundOrder(String id) {
        Order order = getOrder(id);
        if ("REFUNDED".equals(order.getStatus())) {
            throw new ResponseStatusException(HttpStatus.CONFLICT, "Order already refunded");
        }
        order.setStatus("REFUNDED");
        return repository.save(order);
    }
}
