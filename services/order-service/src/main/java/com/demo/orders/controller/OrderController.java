package com.demo.orders.controller;

import com.demo.orders.model.Order;
import com.demo.orders.service.OrderService;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
public class OrderController {

    private final OrderService orderService;

    public OrderController(OrderService orderService) {
        this.orderService = orderService;
    }

    @GetMapping("/health")
    public Map<String, String> health() {
        return Map.of("status", "ok", "service", "order-service");
    }

    @PostMapping("/orders")
    @ResponseStatus(HttpStatus.CREATED)
    public Order createOrder(@RequestBody Map<String, Object> body) {
        @SuppressWarnings("unchecked")
        List<Map<String, Object>> items = (List<Map<String, Object>>) body.get("items");
        String paymentId = (String) body.get("paymentId");
        Double totalAmount = body.get("totalAmount") != null
            ? ((Number) body.get("totalAmount")).doubleValue()
            : 0.0;
        return orderService.createOrder(items, paymentId, totalAmount);
    }

    @GetMapping("/orders")
    public List<Order> getAllOrders() {
        return orderService.getAllOrders();
    }

    @GetMapping("/orders/{id}")
    public Order getOrder(@PathVariable String id) {
        return orderService.getOrder(id);
    }

    @PostMapping("/orders/{id}/refund")
    public Order refundOrder(@PathVariable String id) {
        return orderService.refundOrder(id);
    }
}
